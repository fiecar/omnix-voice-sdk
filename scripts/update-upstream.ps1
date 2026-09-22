#Requires -Version 7.0
<#
.SYNOPSIS
  Skeleton wrapper around import-upstream for documented upstream updates.

.DESCRIPTION
  Does NOT choose versions. Caller (or lead) must already edit
  third_party/SOURCE_MANIFEST.json per Issue #1 §13, then invoke this
  wrapper which delegates to scripts/import-upstream.ps1.

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

$here = $PSScriptRoot
if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Path }
$import = Join-Path $here 'import-upstream.ps1'

if (-not (Test-Path -LiteralPath $import)) {
    [Console]::Error.WriteLine("update-upstream: missing $import")
    exit 1
}

Write-Host "update-upstream: delegating to import-upstream for component=$Component"
Write-Host "update-upstream: ensure SOURCE_MANIFEST.json was edited first (Issue #1 section 13)"
& $import -Component $Component
exit $LASTEXITCODE
