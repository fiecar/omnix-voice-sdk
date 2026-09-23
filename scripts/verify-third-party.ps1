#Requires -Version 7.0
<#
.SYNOPSIS
  Verify vendored third_party trees against TREE_SHA256SUMS (fail closed).
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Fail([string]$Message) {
    [Console]::Error.WriteLine("verify-third-party: $Message")
    exit 1
}

function Test-OmnixSkippedVendoredRel([string]$Rel) {
    $n = $Rel.ToLowerInvariant()
    return ($n -match '\.(pem|key|p12|pfx|jks|keystore|dylib|so|dll|exe|a)$')
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sumsPath = Join-Path $repoRoot 'third_party/TREE_SHA256SUMS'
$manifestPath = Join-Path $repoRoot 'third_party/SOURCE_MANIFEST.json'

if (-not (Test-Path -LiteralPath $sumsPath)) {
    Fail "Missing $sumsPath — run import-upstream first"
}
if (-not (Test-Path -LiteralPath $manifestPath)) {
    Fail "Missing $manifestPath"
}

$expected = @{}
Get-Content -LiteralPath $sumsPath -Encoding utf8 | ForEach-Object {
    $line = $_.Trim()
    if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { return }
    if ($line -notmatch '^([0-9a-fA-F]{64}) [ *](.+)$') {
        Fail "Malformed TREE_SHA256SUMS line: $_"
    }
    $hash = $Matches[1].ToLowerInvariant()
    $rel = $Matches[2].Trim().Replace('\', '/')
    if (Test-OmnixSkippedVendoredRel $rel) { return }
    if ($expected.ContainsKey($rel)) { Fail "Duplicate path in TREE_SHA256SUMS: $rel" }
    $expected[$rel] = $hash
}

if ($expected.Count -eq 0) {
    Fail "TREE_SHA256SUMS is empty"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
$actual = @{}
foreach ($c in $manifest.components) {
    $vendored = Join-Path $repoRoot ([string]$c.vendoredPath)
    if (-not (Test-Path -LiteralPath $vendored)) { continue }
    Get-ChildItem -LiteralPath $vendored -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($repoRoot.Length).TrimStart('\', '/').Replace('\', '/')
        if (Test-OmnixSkippedVendoredRel $rel) { return }
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant()
        $actual[$rel] = $hash
    }
}

$errors = New-Object System.Collections.Generic.List[string]
foreach ($key in ($expected.Keys | Sort-Object)) {
    if (-not $actual.ContainsKey($key)) {
        $errors.Add("MISSING: $key")
        continue
    }
    if ($actual[$key] -ne $expected[$key]) {
        $errors.Add("MODIFIED: $key (expected $($expected[$key]), got $($actual[$key]))")
    }
}
foreach ($key in ($actual.Keys | Sort-Object)) {
    if (-not $expected.ContainsKey($key)) {
        $errors.Add("UNEXPECTED: $key")
    }
}

if ($errors.Count -gt 0) {
    Write-Host "verify-third-party: FAILED ($($errors.Count) issue(s))"
    $errors | ForEach-Object { Write-Host "  $_" }
    $patches = Join-Path $repoRoot 'PATCHES.md'
    Write-Host "If a change is intentional, record it in PATCHES.md and regenerate TREE_SHA256SUMS via import-upstream (lead-approved)."
    if (Test-Path -LiteralPath $patches) {
        Write-Host "PATCHES.md exists — review whether an approved patch entry covers this change."
    }
    exit 1
}

Write-Host "verify-third-party: OK ($($actual.Count) files)"
exit 0
