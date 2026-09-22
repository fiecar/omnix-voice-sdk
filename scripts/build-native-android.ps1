#Requires -Version 7.0
<#
.SYNOPSIS
  Configure and build Omnix native static libs for one Android ABI (SDK-009).

.DESCRIPTION
  Windows verification path from Issue #2 SDK-009:
  cross-compile with the Android NDK (no WSL). Requires:
  - ANDROID_NDK_HOME pointing at NDK ≥ r28
  - cmake + ninja on PATH
  - pinned OpenSSL static libs for the ABI (fetch-openssl-android.ps1)
#>
[CmdletBinding()]
param(
    [ValidateSet('arm64-v8a', 'armeabi-v7a', 'x86_64')]
    [string]$Abi = 'arm64-v8a',
    [string]$AndroidPlatform = 'android-26',
    [string]$BuildDir = '',
    [string]$OpensslRoot = '',
    [switch]$ConfigureOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Fail([string]$Message) {
    [Console]::Error.WriteLine("build-native-android: $Message")
    exit 1
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $BuildDir) {
    $BuildDir = Join-Path $repoRoot "build/android-$Abi"
}
if (-not $OpensslRoot) {
    $OpensslRoot = Join-Path $repoRoot "build/openssl-android/$Abi"
}

$ndk = $env:ANDROID_NDK_HOME
if (-not $ndk) { Fail 'ANDROID_NDK_HOME must point at a pinned NDK ≥ r28' }
$toolchain = Join-Path $ndk 'build/cmake/android.toolchain.cmake'
if (-not (Test-Path -LiteralPath $toolchain)) {
    Fail "NDK toolchain missing: $toolchain"
}
if (-not (Test-Path -LiteralPath (Join-Path $OpensslRoot 'lib/libssl.a'))) {
    Fail "Pinned OpenSSL missing at $OpensslRoot. Run: pwsh -File scripts/fetch-openssl-android.ps1"
}
if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
    Fail 'cmake is required on PATH'
}
if (-not (Get-Command ninja -ErrorAction SilentlyContinue)) {
    Fail 'ninja is required on PATH'
}

Write-Host "build-native-android: ABI=$Abi NDK=$ndk"
Write-Host "build-native-android: OpenSSL=$OpensslRoot"
Write-Host "build-native-android: BuildDir=$BuildDir"

& cmake -S (Join-Path $repoRoot 'cpp') -B $BuildDir -G Ninja `
    "-DCMAKE_TOOLCHAIN_FILE=$toolchain" `
    "-DANDROID_ABI=$Abi" `
    "-DANDROID_PLATFORM=$AndroidPlatform" `
    '-DANDROID_STL=c++_static' `
    '-DSTATIC=ON' `
    "-DOMNIX_OPENSSL_ROOT=$OpensslRoot"
if ($LASTEXITCODE -ne 0) { Fail 'cmake configure failed' }

if ($ConfigureOnly) {
    Write-Host 'build-native-android: configure-only; done'
    exit 0
}

& cmake --build $BuildDir --target re baresip omnix_voice
if ($LASTEXITCODE -ne 0) { Fail 'cmake build failed' }

$reLib = Get-ChildItem -Path $BuildDir -Recurse -Filter 'libre.a' -ErrorAction SilentlyContinue |
    Select-Object -First 1
if (-not $reLib) {
    $reLib = Get-ChildItem -Path $BuildDir -Recurse -Filter 're.a' -ErrorAction SilentlyContinue |
        Select-Object -First 1
}
$baresipLib = Get-ChildItem -Path $BuildDir -Recurse -Filter 'libbaresip.a' -ErrorAction SilentlyContinue |
    Select-Object -First 1
if (-not $baresipLib) {
    $baresipLib = Get-ChildItem -Path $BuildDir -Recurse -Filter 'baresip.a' -ErrorAction SilentlyContinue |
        Select-Object -First 1
}

if (-not $reLib) { Fail 'libre.a / re.a not found in build output' }
if (-not $baresipLib) { Fail 'libbaresip.a not found in build output' }

Write-Host "PASS: $($reLib.FullName)"
Write-Host "PASS: $($baresipLib.FullName)"
Write-Host 'build-native-android: OK'
