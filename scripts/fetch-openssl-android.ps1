#Requires -Version 7.0
<#
.SYNOPSIS
  Download the CI-built static OpenSSL Android artifact for the current commit
  and fail closed if SHA-256 does not match the checksum published by that run.

.DESCRIPTION
  Windows developers do not need WSL to obtain libssl.a/libcrypto.a.
  Canonical build is Linux CI (.github/workflows/android.yml).
  This script downloads the artifact for the git commit that matches HEAD
  (or -CommitSha) and verifies SHA256SUMS before extracting.
#>
[CmdletBinding()]
param(
    [string]$CommitSha = '',
    [string]$OutDir = '',
    [string]$Repo = 'fiecar/omnix-voice-sdk',
    [string]$Workflow = 'android.yml',
    [string]$ArtifactNamePrefix = 'openssl-android'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Fail([string]$Message) {
    [Console]::Error.WriteLine("fetch-openssl-android: $Message")
    exit 1
}

function Get-RepoRoot {
    $here = $PSScriptRoot
    if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Path }
    return (Resolve-Path (Join-Path $here '..')).Path
}

function Get-FileSha256Lower([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$repoRoot = Get-RepoRoot
if (-not $OutDir) { $OutDir = Join-Path $repoRoot 'build/openssl-android' }
if (-not $CommitSha) {
    $CommitSha = (git -C $repoRoot rev-parse HEAD).Trim().ToLowerInvariant()
}
$CommitSha = $CommitSha.Trim().ToLowerInvariant()
if ($CommitSha -notmatch '^[0-9a-f]{40}$') {
    Fail "CommitSha must be a full 40-char SHA (got: $CommitSha)"
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Fail "GitHub CLI (gh) is required"
}

Write-Host "fetch-openssl-android: looking for successful '$Workflow' run for commit $CommitSha"

# Find the newest successful workflow run for this commit
$runsJson = gh api "repos/$Repo/actions/workflows/$Workflow/runs?head_sha=$CommitSha&status=completed&per_page=20" 2>&1
if ($LASTEXITCODE -ne 0) {
    Fail "Failed to query workflow runs: $runsJson"
}
$runs = $runsJson | ConvertFrom-Json
$run = @($runs.workflow_runs | Where-Object { $_.conclusion -eq 'success' } | Select-Object -First 1)
if (-not $run) {
    Fail "No successful $Workflow run found for commit $CommitSha. Push the branch and wait for CI, or build via WSL: scripts/build-openssl-android.sh"
}

$runId = $run.id
Write-Host "fetch-openssl-android: using run id=$runId url=$($run.html_url)"

$artsJson = gh api "repos/$Repo/actions/runs/$runId/artifacts"
if ($LASTEXITCODE -ne 0) { Fail "Failed to list artifacts for run $runId" }
$arts = $artsJson | ConvertFrom-Json
$art = @($arts.artifacts | Where-Object { $_.name -like "$ArtifactNamePrefix*" -and -not $_.expired } | Select-Object -First 1)
if (-not $art) {
    Fail "No artifact matching '$ArtifactNamePrefix*' on run $runId"
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("omnix-openssl-fetch-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $work | Out-Null
$zipPath = Join-Path $work 'artifact.zip'
$extract = Join-Path $work 'extract'

try {
    Write-Host "fetch-openssl-android: downloading artifact '$($art.name)' (id=$($art.id))"
    gh api "repos/$Repo/actions/artifacts/$($art.id)/zip" > $zipPath
    if (-not (Test-Path -LiteralPath $zipPath) -or (Get-Item -LiteralPath $zipPath).Length -le 0) {
        Fail "Downloaded artifact zip is empty"
    }

    New-Item -ItemType Directory -Force -Path $extract | Out-Null
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extract -Force

    $sumsPath = Get-ChildItem -LiteralPath $extract -Recurse -Filter 'SHA256SUMS' | Select-Object -First 1
    if (-not $sumsPath) { Fail "SHA256SUMS missing from artifact" }

    Write-Host "fetch-openssl-android: verifying SHA256SUMS"
    $sumsDir = $sumsPath.Directory.FullName
    foreach ($line in Get-Content -LiteralPath $sumsPath.FullName) {
        $trim = $line.Trim()
        if (-not $trim -or $trim.StartsWith('#')) { continue }
        # format: <sha256>  <relative-path>  OR  <sha256> *<path>
        if ($trim -notmatch '^([0-9a-fA-F]{64})\s+\*?(.+)$') {
            Fail "Malformed SHA256SUMS line: $trim"
        }
        $expected = $Matches[1].ToLowerInvariant()
        $rel = $Matches[2].Trim()
        $file = Join-Path $sumsDir $rel
        if (-not (Test-Path -LiteralPath $file)) { Fail "Checksum path missing: $rel" }
        $actual = Get-FileSha256Lower $file
        if ($actual -ne $expected) {
            Fail "SHA-256 mismatch for $rel`nExpected: $expected`nActual:   $actual"
        }
        Write-Host "fetch-openssl-android: OK $rel"
    }

    # Fail closed if shared libs present
    $shared = Get-ChildItem -LiteralPath $extract -Recurse -Include 'libssl.so*','libcrypto.so*' -ErrorAction SilentlyContinue
    if ($shared) {
        Fail "Artifact contains shared OpenSSL libraries (forbidden)"
    }

    if (Test-Path -LiteralPath $OutDir) {
        Remove-Item -LiteralPath $OutDir -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    Copy-Item -Path (Join-Path $sumsDir '*') -Destination $OutDir -Recurse -Force

    Write-Host "fetch-openssl-android: SUCCESS -> $OutDir (verified against run $runId)"
    exit 0
}
finally {
    if (Test-Path -LiteralPath $work) {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}
