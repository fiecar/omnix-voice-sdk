#Requires -Version 7.0
<#
.SYNOPSIS
  Generate SBOM.json (SPDX 2.3) using pinned syft, then enrich from SOURCE_MANIFEST.json.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Pin — do not use "latest"
$Script:SyftVersion = '1.52.0'
$Script:SyftLicense = 'Apache-2.0'

function Fail([string]$Message) {
    [Console]::Error.WriteLine("generate-sbom: $Message")
    exit 1
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $repoRoot

$manifestPath = Join-Path $repoRoot 'third_party/SOURCE_MANIFEST.json'
$outPath = Join-Path $repoRoot 'SBOM.json'
$enrichScript = Join-Path $PSScriptRoot 'enrich-sbom.js'

if (-not (Test-Path -LiteralPath $manifestPath)) {
    Fail "Missing third_party/SOURCE_MANIFEST.json"
}
if (-not (Test-Path -LiteralPath (Join-Path $repoRoot 'LICENSES'))) {
    Fail "Missing LICENSES/"
}
if (-not (Test-Path -LiteralPath $enrichScript)) {
    Fail "Missing scripts/enrich-sbom.js"
}

function Get-SyftExe {
    $cache = Join-Path $env:LOCALAPPDATA "omnix-voice-sdk\tools\syft\v$Script:SyftVersion"
    $exe = Join-Path $cache 'syft.exe'
    if (Test-Path -LiteralPath $exe) {
        return $exe
    }
    New-Item -ItemType Directory -Force -Path $cache | Out-Null
    $zip = Join-Path $cache 'syft.zip'
    $url = "https://github.com/anchore/syft/releases/download/v$Script:SyftVersion/syft_$($Script:SyftVersion)_windows_amd64.zip"
    Write-Host "generate-sbom: downloading pinned syft v$Script:SyftVersion"
    Write-Host "generate-sbom: $url"
    try {
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    }
    catch {
        Fail "Failed to download syft: $($_.Exception.Message)"
    }
    Expand-Archive -LiteralPath $zip -DestinationPath $cache -Force
    if (-not (Test-Path -LiteralPath $exe)) {
        Fail "syft.exe missing after extract in $cache"
    }
    return $exe
}

$syft = Get-SyftExe
Write-Host "generate-sbom: tool=syft version=$Script:SyftVersion license=$Script:SyftLicense"
& $syft version
if ($LASTEXITCODE -ne 0) { Fail "syft version failed" }

$rawPath = Join-Path ([System.IO.Path]::GetTempPath()) ("omnix-sbom-raw-" + [guid]::NewGuid().ToString('N') + '.json')

# Exclude vendored third_party from auto-discovery (CI workflow noise); inject from manifest instead.
Write-Host "generate-sbom: scanning repository (excluding third_party and .git)"
& $syft dir:. `
    --exclude './third_party/**' `
    --exclude './.git/**' `
    --source-name 'omnix-voice-sdk' `
    -o "spdx-json=$rawPath"
if ($LASTEXITCODE -ne 0) {
    Remove-Item -LiteralPath $rawPath -Force -ErrorAction SilentlyContinue
    Fail "syft scan failed (exit $LASTEXITCODE)"
}

Write-Host "generate-sbom: enriching from SOURCE_MANIFEST.json"
node $enrichScript --input $rawPath --output $outPath --manifest $manifestPath --repo-root $repoRoot
if ($LASTEXITCODE -ne 0) {
    Remove-Item -LiteralPath $rawPath -Force -ErrorAction SilentlyContinue
    Fail "enrich-sbom.js failed"
}

Remove-Item -LiteralPath $rawPath -Force -ErrorAction SilentlyContinue
Write-Host "generate-sbom: wrote $outPath"
exit 0
