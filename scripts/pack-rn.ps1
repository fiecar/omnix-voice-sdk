<#
.SYNOPSIS
  Pack @omnix/voice-sdk npm tarball (SDK-046).

.DESCRIPTION
  1. Locates OmnixVoiceSDK-x.y.z.aar (build or existing artifact)
  2. Installs it into react-native/android/maven Maven layout + POM
  3. Optionally copies OmnixVoiceSDK.xcframework into react-native/ios/ if present
  4. Copies THIRD_PARTY_NOTICES.md into the package root
  5. Runs npm pack -> dist/omnix-voice-sdk-x.y.z.tgz
#>
[CmdletBinding()]
param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
  [string]$Version = '0.1.0'
)

$ErrorActionPreference = 'Stop'

function Fail([string]$Message) {
  Write-Error "pack-rn: $Message"
  exit 1
}

$rnDir = Join-Path $RepoRoot 'react-native'
$distDir = Join-Path $RepoRoot 'dist'
$mavenRoot = Join-Path $rnDir "android/maven/com/omnix/voice/omnix-voice-sdk/$Version"
$aarName = "OmnixVoiceSDK-$Version.aar"
$groupPath = 'com/omnix/voice'

if (-not (Test-Path -LiteralPath (Join-Path $rnDir 'package.json'))) {
  Fail "missing react-native/package.json"
}

New-Item -ItemType Directory -Force -Path $distDir | Out-Null
New-Item -ItemType Directory -Force -Path $mavenRoot | Out-Null

# --- Locate AAR ---
$aarCandidates = @(
  (Join-Path $RepoRoot "android/build/outputs/aar/$aarName"),
  (Join-Path $RepoRoot "android/build/outputs/aar/OmnixVoiceSDK-release.aar"),
  (Join-Path $distDir $aarName)
) | Where-Object { Test-Path -LiteralPath $_ }

$aar = $aarCandidates | Select-Object -First 1
if (-not $aar) {
  Write-Host "pack-rn: AAR not found — building android assembleRelease"
  Push-Location (Join-Path $RepoRoot 'android')
  try {
    if (Test-Path '.\gradlew.bat') {
      & .\gradlew.bat assembleRelease --no-daemon
    } elseif (Test-Path '.\gradlew') {
      & .\gradlew assembleRelease --no-daemon
    } else {
      Fail "gradlew not found under android/"
    }
    if ($LASTEXITCODE -ne 0) { Fail "assembleRelease failed" }
  } finally {
    Pop-Location
  }
  $aar = Join-Path $RepoRoot "android/build/outputs/aar/$aarName"
  if (-not (Test-Path -LiteralPath $aar)) {
    $aar = Get-ChildItem (Join-Path $RepoRoot 'android/build/outputs/aar') -Filter 'OmnixVoiceSDK-*.aar' |
      Select-Object -First 1 -ExpandProperty FullName
  }
}
if (-not $aar -or -not (Test-Path -LiteralPath $aar)) {
  Fail "OmnixVoiceSDK AAR not found after build"
}

$destAar = Join-Path $mavenRoot "omnix-voice-sdk-$Version.aar"
Copy-Item -LiteralPath $aar -Destination $destAar -Force
Write-Host "pack-rn: installed AAR -> $destAar"

# Maven POM (minimal)
$pom = @"
<?xml version="1.0" encoding="UTF-8"?>
<project xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd"
         xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.omnix.voice</groupId>
  <artifactId>omnix-voice-sdk</artifactId>
  <version>$Version</version>
  <packaging>aar</packaging>
  <name>Omnix Voice SDK</name>
  <description>Omnix Voice Android AAR consumed by @omnix/voice-sdk</description>
</project>
"@
Set-Content -LiteralPath (Join-Path $mavenRoot "omnix-voice-sdk-$Version.pom") -Value $pom -Encoding utf8

# maven-metadata.xml (simple)
$meta = @"
<?xml version="1.0" encoding="UTF-8"?>
<metadata>
  <groupId>com.omnix.voice</groupId>
  <artifactId>omnix-voice-sdk</artifactId>
  <versioning>
    <release>$Version</release>
    <versions><version>$Version</version></versions>
    <lastUpdated>$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))</lastUpdated>
  </versioning>
</metadata>
"@
Set-Content -LiteralPath (Join-Path $rnDir 'android/maven/com/omnix/voice/omnix-voice-sdk/maven-metadata.xml') -Value $meta -Encoding utf8

# Optional XCFramework (SDK-043 may be BLOCKED)
$xcfSrc = Join-Path $RepoRoot 'dist/OmnixVoiceSDK.xcframework'
$xcfDst = Join-Path $rnDir 'ios/OmnixVoiceSDK.xcframework'
if (Test-Path -LiteralPath $xcfSrc) {
  if (Test-Path -LiteralPath $xcfDst) { Remove-Item -Recurse -Force $xcfDst }
  Copy-Item -Recurse -LiteralPath $xcfSrc -Destination $xcfDst
  Write-Host "pack-rn: copied OmnixVoiceSDK.xcframework into react-native/ios/"
} else {
  Write-Host "pack-rn: WARN — OmnixVoiceSDK.xcframework not present (SDK-043); podspec will omit vendored_frameworks"
}

# Notices
Copy-Item -LiteralPath (Join-Path $RepoRoot 'THIRD_PARTY_NOTICES.md') `
  -Destination (Join-Path $rnDir 'THIRD_PARTY_NOTICES.md') -Force

# Nested .gitignore under android/maven ignores *.aar; npm would exclude it.
# Temporarily rename for pack so the AAR is included in the tarball.
$mavenGitIgnore = Join-Path $rnDir 'android/maven/.gitignore'
$mavenGitIgnoreBak = "$mavenGitIgnore.packbak"
if (Test-Path -LiteralPath $mavenGitIgnore) {
  Move-Item -LiteralPath $mavenGitIgnore -Destination $mavenGitIgnoreBak -Force
}

# npm pack
Push-Location $rnDir
try {
  if (-not (Test-Path 'package-lock.json')) {
    Write-Host "pack-rn: npm install (generate package-lock)"
    npm install --ignore-scripts --no-fund --no-audit --legacy-peer-deps
    if ($LASTEXITCODE -ne 0) { Fail "npm install failed" }
  }
  npm pack --pack-destination $distDir
  if ($LASTEXITCODE -ne 0) { Fail "npm pack failed" }
} finally {
  Pop-Location
  if (Test-Path -LiteralPath $mavenGitIgnoreBak) {
    Move-Item -LiteralPath $mavenGitIgnoreBak -Destination $mavenGitIgnore -Force
  }
}

$tgz = Join-Path $distDir "omnix-voice-sdk-$Version.tgz"
# npm pack may emit omnix-voice-sdk-0.1.0.tgz (without scope) or @omnix-voice-sdk-...
$found = Get-ChildItem $distDir -Filter "*omnix-voice-sdk*$Version*.tgz" | Select-Object -First 1
if (-not $found) { Fail "tarball not produced in dist/" }
if ($found.FullName -ne $tgz) {
  Copy-Item -LiteralPath $found.FullName -Destination $tgz -Force
}
Write-Host "pack-rn: SUCCESS -> $tgz"
Get-FileHash -Algorithm SHA256 -LiteralPath $tgz | Format-List
