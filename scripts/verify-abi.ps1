#Requires -Version 7.0
<#
.SYNOPSIS
  SDK-037 — verify all 3 Android ABIs present in a release AAR.
  Semantics match scripts/verify-abi.sh.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Aar
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Aar)) {
    Write-Error "ERROR: AAR not found: $Aar"
    exit 1
}

# Force array: a single-entry tar listing must not become a character enumeration.
$entries = @(tar -tf $Aar 2>$null)
if ($LASTEXITCODE -ne 0) { throw "Cannot read $Aar" }

$failed = $false
foreach ($abi in 'arm64-v8a', 'armeabi-v7a', 'x86_64') {
    if ($entries -contains "jni/$abi/libomnixvoice.so") {
        "OK: $abi"
    }
    else {
        "ERROR: Missing $abi"
        $failed = $true
    }
}
if ($failed) { exit 1 }
