#Requires -Version 7.0
<#
.SYNOPSIS
  Fail-closed, commit-anchored import of a vendored upstream component.

.DESCRIPTION
  Reads third_party/SOURCE_MANIFEST.json (never "latest"). Downloads by exact
  commit SHA archive URL, verifies tag→commit and git get-tar-commit-id,
  records/checks archiveSha256, atomically replaces the vendored tree, and
  regenerates SHA256SUMS + TREE_SHA256SUMS.

.PARAMETER Component
  Component name from SOURCE_MANIFEST.json (e.g. baresip, re).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Component
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Fail([string]$Message) {
    [Console]::Error.WriteLine("import-upstream: $Message")
    exit 1
}

function Get-RepoRoot {
    $here = $PSScriptRoot
    if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Path }
    return (Resolve-Path (Join-Path $here '..')).Path
}

function Read-Manifest([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        Fail "SOURCE_MANIFEST.json not found at $Path"
    }
    return (Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json)
}

function Write-Manifest($Manifest, [string]$Path) {
    $json = $Manifest | ConvertTo-Json -Depth 10
    # Normalize to LF for committed JSON stability
    $json = $json -replace "`r`n", "`n"
    if (-not $json.EndsWith("`n")) { $json += "`n" }
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

function Test-ForbiddenUrl([string]$Url) {
    $u = $Url.ToLowerInvariant()
    if ($u -match '/tarball/') { return $true }
    if ($u -match '/archive/refs/heads/') { return $true }
    if ($u -match '/archive/main\.|/archive/master\.') { return $true }
    if ($u -match '[?&]ref=(main|master)\b') { return $true }
    return $false
}

function Get-TagCommit([string]$Repository, [string]$Version) {
    $peeled = git ls-remote $Repository "refs/tags/$Version^{}" 2>$null
    if ($LASTEXITCODE -ne 0) { Fail "git ls-remote failed for $Repository tags/$Version^{}" }
    $line = ($peeled | Where-Object { $_ -match '\S' } | Select-Object -First 1)
    if ($line) {
        return ($line -split '\s+')[0].ToLowerInvariant()
    }
    $light = git ls-remote $Repository "refs/tags/$Version" 2>$null
    if ($LASTEXITCODE -ne 0) { Fail "git ls-remote failed for $Repository tags/$Version" }
    $line = ($light | Where-Object { $_ -match '\S' } | Select-Object -First 1)
    if (-not $line) { Fail "Tag refs/tags/$Version not found on $Repository" }
    return ($line -split '\s+')[0].ToLowerInvariant()
}

function Get-TarCommitId([string]$TarPath) {
    # git get-tar-commit-id reads only the archive header, then closes stdin early.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'git'
    $psi.Arguments = 'get-tar-commit-id'
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $inStream = [System.IO.File]::OpenRead($TarPath)
    try {
        try {
            $inStream.CopyTo($proc.StandardInput.BaseStream)
            $proc.StandardInput.Close()
        }
        catch [System.IO.IOException] {
            # Expected: git closes the pipe after reading the commit id header.
            try { $proc.StandardInput.Close() } catch { }
        }
    }
    finally {
        $inStream.Dispose()
    }
    $stdout = $proc.StandardOutput.ReadToEnd().Trim()
    $stderr = $proc.StandardError.ReadToEnd().Trim()
    $proc.WaitForExit()
    $token = if ([string]::IsNullOrWhiteSpace($stdout)) { '' } else { (($stdout -split '\s+')[0]).ToLowerInvariant() }
    if ($token -notmatch '^[0-9a-f]{40}$') {
        Fail "git get-tar-commit-id failed (exit $($proc.ExitCode)): stdout='$stdout' stderr='$stderr'"
    }
    return $token
}

function Expand-Gzip([string]$GzPath, [string]$TarPath) {
    $in = [System.IO.File]::OpenRead($GzPath)
    try {
        $gzip = New-Object System.IO.Compression.GZipStream($in, [System.IO.Compression.CompressionMode]::Decompress)
        try {
            $out = [System.IO.File]::Create($TarPath)
            try { $gzip.CopyTo($out) }
            finally { $out.Dispose() }
        }
        finally { $gzip.Dispose() }
    }
    finally { $in.Dispose() }
}

function Get-FileSha256Lower([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Write-Sha256Sums([string]$RepoRoot, $Manifest) {
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($c in $Manifest.components) {
        if ([string]::IsNullOrWhiteSpace([string]$c.archiveSha256)) { continue }
        $name = "{0}-{1}.tar.gz" -f $c.component, $c.commit
        $lines.Add(("{0}  {1}" -f ([string]$c.archiveSha256).ToLowerInvariant(), $name))
    }
    $path = Join-Path $RepoRoot 'third_party/SHA256SUMS'
    $text = ($lines -join "`n")
    if ($text.Length -gt 0) { $text += "`n" }
    [System.IO.File]::WriteAllText($path, $text, [System.Text.UTF8Encoding]::new($false))
}

function Write-TreeSha256Sums([string]$RepoRoot, $Manifest) {
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($c in $Manifest.components) {
        $vendored = Join-Path $RepoRoot ([string]$c.vendoredPath)
        if (-not (Test-Path -LiteralPath $vendored)) { continue }
        $files = Get-ChildItem -LiteralPath $vendored -Recurse -File
        foreach ($f in $files) {
            $rel = $f.FullName.Substring($RepoRoot.Length).TrimStart('\', '/').Replace('\', '/')
            $hash = Get-FileSha256Lower $f.FullName
            $lines.Add(("{0}  {1}" -f $hash, $rel))
        }
    }
    $sorted = $lines | Sort-Object { ($_ -split '  ', 2)[1] }
    $path = Join-Path $RepoRoot 'third_party/TREE_SHA256SUMS'
    $text = ($sorted -join "`n")
    if ($text.Length -gt 0) { $text += "`n" }
    [System.IO.File]::WriteAllText($path, $text, [System.Text.UTF8Encoding]::new($false))
}

function Update-UpstreamMd([string]$RepoRoot, $Entry) {
    $path = Join-Path $RepoRoot 'UPSTREAM.md'
    $line = ("{0}: tag={1}, commit={2}, imported={3}, license={4}, archive-sha256={5}" -f `
        $Entry.component, $Entry.version, $Entry.commit, $Entry.importDate, $Entry.license, $Entry.archiveSha256)
    $marker = "<!-- IMPORT:$($Entry.component) -->"
    $block = @"
$marker
$line
"@
    if (Test-Path -LiteralPath $path) {
        $existing = Get-Content -LiteralPath $path -Raw -Encoding utf8
        if ($existing -match [regex]::Escape($marker)) {
            $existing = [regex]::Replace($existing, "(?s)$([regex]::Escape($marker))\r?\n.*?(?=\r?\n<!-- IMPORT:|\r?\n## |\z)", $block.TrimEnd() + "`n")
        }
        else {
            if (-not $existing.EndsWith("`n")) { $existing += "`n" }
            $existing += "`n## Imported components`n`n$block`n"
        }
        $existing = $existing -replace "`r`n", "`n"
        [System.IO.File]::WriteAllText($path, $existing, [System.Text.UTF8Encoding]::new($false))
    }
}

# --- main ---
$repoRoot = Get-RepoRoot
$manifestPath = Join-Path $repoRoot 'third_party/SOURCE_MANIFEST.json'
$manifest = Read-Manifest $manifestPath

$entry = $manifest.components | Where-Object { $_.component -eq $Component } | Select-Object -First 1
if (-not $entry) { Fail "Component '$Component' not found in SOURCE_MANIFEST.json" }

$commit = ([string]$entry.commit).ToLowerInvariant()
$version = [string]$entry.version
$repository = [string]$entry.repository
$downloadUrl = [string]$entry.downloadUrl
$vendoredRel = [string]$entry.vendoredPath
$vendoredPath = Join-Path $repoRoot $vendoredRel
$expectedUrl = "{0}/archive/{1}.tar.gz" -f $repository.TrimEnd('/'), $commit

if ([string]::IsNullOrWhiteSpace($commit) -or $commit -notmatch '^[0-9a-f]{40}$') {
    Fail "Manifest commit must be a full 40-char SHA for '$Component'"
}
if (Test-ForbiddenUrl $downloadUrl) {
    Fail "Forbidden download URL (branch/tarball/floating ref): $downloadUrl"
}
if ($downloadUrl -ne $expectedUrl) {
    Fail "downloadUrl must be exact commit archive URL.`nExpected: $expectedUrl`nActual:   $downloadUrl"
}
if ($downloadUrl -notmatch [regex]::Escape($commit)) {
    Fail "downloadUrl does not contain manifest commit SHA"
}

Write-Host "import-upstream: component=$Component commit=$commit"

# 1) Tag → commit
$tagCommit = Get-TagCommit -Repository $repository -Version $version
if ($tagCommit -ne $commit) {
    Fail "Tag $version resolves to $tagCommit but manifest commit is $commit"
}
Write-Host "import-upstream: tag $version -> $tagCommit (ok)"

# Work in temp; never touch third_party until success
$work = Join-Path ([System.IO.Path]::GetTempPath()) ("omnix-import-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $work | Out-Null
$archiveName = "{0}-{1}.tar.gz" -f $Component, $commit
$gzPath = Join-Path $work $archiveName
$tarPath = Join-Path $work ("{0}-{1}.tar" -f $Component, $commit)
$extractRoot = Join-Path $work 'extract'
$stagePath = Join-Path $work 'stage'

try {
    New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null

    Write-Host "import-upstream: downloading $downloadUrl"
    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $gzPath -UseBasicParsing
    }
    catch {
        Fail "Download failed: $($_.Exception.Message)"
    }
    if (-not (Test-Path -LiteralPath $gzPath) -or (Get-Item -LiteralPath $gzPath).Length -le 0) {
        Fail "Download produced empty file"
    }

    $computed = Get-FileSha256Lower $gzPath
    Write-Host "import-upstream: archive SHA-256 = $computed"

    $recorded = ([string]$entry.archiveSha256).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($recorded)) {
        Write-Host "import-upstream: first import — recording archiveSha256"
        $entry.archiveSha256 = $computed
    }
    elseif ($recorded -ne $computed) {
        Fail "archiveSha256 mismatch for $Component.`nRecorded: $recorded`nComputed: $computed"
    }
    else {
        Write-Host "import-upstream: archiveSha256 matches recorded value"
    }

    Expand-Gzip -GzPath $gzPath -TarPath $tarPath
    $tarCommit = Get-TarCommitId -TarPath $tarPath
    if ($tarCommit -ne $commit) {
        Fail "Archive commit-id $tarCommit does not match manifest commit $commit"
    }
    Write-Host "import-upstream: git get-tar-commit-id -> $tarCommit (ok)"

    & tar -xzf $gzPath -C $extractRoot
    if ($LASTEXITCODE -ne 0) { Fail "tar extract failed (exit $LASTEXITCODE)" }

    $top = @(Get-ChildItem -LiteralPath $extractRoot -Directory)
    if ($top.Count -ne 1) {
        Fail "Unexpected archive layout: expected exactly one top-level directory, found $($top.Count)"
    }
    $sourceTree = $top[0].FullName

    $licensePath = Join-Path $sourceTree 'LICENSE'
    if (-not (Test-Path -LiteralPath $licensePath)) {
        $licensePath = Join-Path $sourceTree 'COPYING'
    }
    if (-not (Test-Path -LiteralPath $licensePath)) {
        Fail "LICENSE/COPYING missing in extracted tree"
    }

    # Stage tree (contents of top-level dir)
    if (Test-Path -LiteralPath $stagePath) { Remove-Item -LiteralPath $stagePath -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $stagePath | Out-Null
    & tar -cf - -C $sourceTree . | tar -xf - -C $stagePath
    if ($LASTEXITCODE -ne 0) { Fail "Failed to stage extracted tree" }

    $stageLicense = Join-Path $stagePath 'LICENSE'
    if (-not (Test-Path -LiteralPath $stageLicense)) {
        $stageLicense = Join-Path $stagePath 'COPYING'
    }
    if (-not (Test-Path -LiteralPath $stageLicense)) {
        Fail "LICENSE missing after staging"
    }

    # Atomic replace
    $backup = $null
    $parent = Split-Path -Parent $vendoredPath
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    if (Test-Path -LiteralPath $vendoredPath) {
        $backup = "$vendoredPath.__bak_$PID"
        if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Recurse -Force }
        Move-Item -LiteralPath $vendoredPath -Destination $backup
    }
    try {
        Move-Item -LiteralPath $stagePath -Destination $vendoredPath
    }
    catch {
        if ($backup -and (Test-Path -LiteralPath $backup)) {
            if (Test-Path -LiteralPath $vendoredPath) { Remove-Item -LiteralPath $vendoredPath -Recurse -Force }
            Move-Item -LiteralPath $backup -Destination $vendoredPath
        }
        Fail "Failed to replace vendored tree: $($_.Exception.Message)"
    }
    if ($backup -and (Test-Path -LiteralPath $backup)) {
        Remove-Item -LiteralPath $backup -Recurse -Force
    }

    # Metadata
    $entry.importDate = (Get-Date -Format 'yyyy-MM-dd')
    $entry.archiveSha256 = $computed

    # Copy license verbatim into LICENSES/
    $licensesDir = Join-Path $repoRoot 'LICENSES'
    New-Item -ItemType Directory -Force -Path $licensesDir | Out-Null
    $licenseDest = Join-Path $licensesDir ("{0}-LICENSE.txt" -f $Component)
    $vendoredLicense = Join-Path $vendoredPath 'LICENSE'
    if (-not (Test-Path -LiteralPath $vendoredLicense)) {
        $vendoredLicense = Join-Path $vendoredPath 'COPYING'
    }
    Copy-Item -LiteralPath $vendoredLicense -Destination $licenseDest -Force

    Write-Manifest -Manifest $manifest -Path $manifestPath
    Write-Sha256Sums -RepoRoot $repoRoot -Manifest $manifest
    Write-TreeSha256Sums -RepoRoot $repoRoot -Manifest $manifest
    Update-UpstreamMd -RepoRoot $repoRoot -Entry $entry

    # Remove placeholder gitkeep under third_party if present and unused
    $gitkeep = Join-Path $repoRoot 'third_party/.gitkeep'
    if (Test-Path -LiteralPath $gitkeep) {
        Remove-Item -LiteralPath $gitkeep -Force -ErrorAction SilentlyContinue
    }
    $licensesKeep = Join-Path $repoRoot 'LICENSES/.gitkeep'
    if ((Test-Path -LiteralPath $licensesKeep) -and (Get-ChildItem -LiteralPath $licensesDir -File | Where-Object { $_.Name -ne '.gitkeep' })) {
        Remove-Item -LiteralPath $licensesKeep -Force -ErrorAction SilentlyContinue
    }

    Write-Host "import-upstream: SUCCESS — $Component @ $commit -> $vendoredRel"
    exit 0
}
catch {
    Fail $_.Exception.Message
}
finally {
    if (Test-Path -LiteralPath $work) {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}
