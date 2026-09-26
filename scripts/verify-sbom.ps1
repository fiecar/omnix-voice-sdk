#Requires -Version 7.0
<#
.SYNOPSIS
  Verify SBOM.json baseline against SOURCE_MANIFEST.json and SDK-008 acceptance rules.
#>
[CmdletBinding()]
param(
    [string]$SbomPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Fail([string]$Message) {
    [Console]::Error.WriteLine("verify-sbom: $Message")
    exit 1
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $SbomPath) { $SbomPath = Join-Path $repoRoot 'SBOM.json' }
$manifestPath = Join-Path $repoRoot 'third_party/SOURCE_MANIFEST.json'

if (-not (Test-Path -LiteralPath $SbomPath)) { Fail "Missing SBOM: $SbomPath" }
if (-not (Test-Path -LiteralPath $manifestPath)) { Fail "Missing manifest" }

$sbomText = Get-Content -LiteralPath $SbomPath -Raw -Encoding utf8
try {
    $sbom = $sbomText | ConvertFrom-Json
}
catch {
    Fail "SBOM.json is not valid JSON: $($_.Exception.Message)"
}

if (-not $sbom.spdxVersion -or ($sbom.spdxVersion -notmatch '^SPDX-2\.')) {
    Fail "Expected SPDX-2.x, got: $($sbom.spdxVersion)"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
$packages = @($sbom.packages)
function Find-Pkg([string]$Name) {
    return $packages | Where-Object { $_.name -eq $Name } | Select-Object -First 1
}

$omnix = Find-Pkg 'omnix-voice-sdk'
if (-not $omnix) { Fail 'Missing package omnix-voice-sdk' }

$baresip = Find-Pkg 'baresip'
if (-not $baresip) { Fail 'Missing package baresip' }
$re = Find-Pkg 're'
if (-not $re) { Fail 'Missing package re' }

$mb = $manifest.components | Where-Object { $_.component -eq 'baresip' } | Select-Object -First 1
$mr = $manifest.components | Where-Object { $_.component -eq 're' } | Select-Object -First 1

$bv = ([string]$baresip.versionInfo).TrimStart('v')
$rv = ([string]$re.versionInfo).TrimStart('v')
$mbv = ([string]$mb.version).TrimStart('v')
$mrv = ([string]$mr.version).TrimStart('v')

if ($bv -ne '4.11.0' -or $bv -ne $mbv) { Fail "baresip version mismatch: sbom=$bv manifest=$mbv" }
if ($rv -ne '4.11.0' -or $rv -ne $mrv) { Fail "re version mismatch: sbom=$rv manifest=$mrv" }

if ([string]$baresip.licenseConcluded -ne 'BSD-3-Clause' -or [string]$baresip.licenseDeclared -ne 'BSD-3-Clause') {
    Fail "baresip license must be BSD-3-Clause"
}
if ([string]$re.licenseConcluded -ne 'BSD-3-Clause' -or [string]$re.licenseDeclared -ne 'BSD-3-Clause') {
    Fail "re license must be BSD-3-Clause"
}

if ([string]$baresip.comment -notmatch [regex]::Escape([string]$mb.commit)) {
    Fail "baresip commit SHA not recorded in SBOM package comment"
}
if ([string]$re.comment -notmatch [regex]::Escape([string]$mr.commit)) {
    Fail "re commit SHA not recorded in SBOM package comment"
}

$rels = @($sbom.relationships)
function Has-Rel([string]$From, [string]$Type, [string]$To) {
    return $null -ne ($rels | Where-Object {
        $_.spdxElementId -eq $From -and $_.relationshipType -eq $Type -and $_.relatedSpdxElement -eq $To
    } | Select-Object -First 1)
}

if (-not (Has-Rel 'SPDXRef-DOCUMENT' 'DESCRIBES' 'SPDXRef-Package-omnix-voice-sdk')) {
    Fail 'Missing DOCUMENT DESCRIBES omnix-voice-sdk'
}
if (-not (Has-Rel 'SPDXRef-Package-omnix-voice-sdk' 'DEPENDS_ON' 'SPDXRef-Package-baresip')) {
    Fail 'Missing omnix-voice-sdk DEPENDS_ON baresip'
}
if (-not (Has-Rel 'SPDXRef-Package-baresip' 'DEPENDS_ON' 'SPDXRef-Package-re')) {
    Fail 'Missing baresip DEPENDS_ON re'
}

$openssl = Find-Pkg 'openssl'
$mo = $manifest.components | Where-Object { $_.component -eq 'openssl' } | Select-Object -First 1
if ($mo -and $mo.archiveSha256) {
    if (-not $openssl) { Fail 'Missing package openssl (present in SOURCE_MANIFEST)' }
    $ov = ([string]$openssl.versionInfo).TrimStart('v')
    $mov = ([string]$mo.version) -replace '^openssl-', ''
    if ($ov -ne $mov -and ([string]$openssl.versionInfo) -ne ([string]$mo.version)) {
        # Accept either "3.5.8" or "openssl-3.5.8" in SBOM versionInfo
        if ($ov -ne ([string]$mo.version).TrimStart('v') -and $ov -ne $mov) {
            Fail "openssl version mismatch: sbom=$($openssl.versionInfo) manifest=$($mo.version)"
        }
    }
    if ([string]$openssl.licenseConcluded -ne 'Apache-2.0' -or [string]$openssl.licenseDeclared -ne 'Apache-2.0') {
        Fail 'openssl license must be Apache-2.0'
    }
    if ([string]$openssl.comment -notmatch [regex]::Escape([string]$mo.commit)) {
        Fail 'openssl commit SHA not recorded in SBOM package comment'
    }
    if (-not (Has-Rel 'SPDXRef-Package-omnix-voice-sdk' 'DEPENDS_ON' 'SPDXRef-Package-openssl')) {
        Fail 'Missing omnix-voice-sdk DEPENDS_ON openssl'
    }
}

foreach ($c in @($manifest.components)) {
    if (-not $c.archiveSha256) { continue }
    $pkg = Find-Pkg ([string]$c.component)
    if (-not $pkg) { Fail "Missing package $($c.component) (present in SOURCE_MANIFEST)" }
    if ([string]$pkg.comment -notmatch [regex]::Escape([string]$c.commit)) {
        Fail "$($c.component) commit SHA not recorded in SBOM package comment"
    }
    if ([string]$pkg.licenseConcluded -ne [string]$c.license) {
        Fail "$($c.component) licenseConcluded must be $($c.license)"
    }
    $runtime = @('baresip', 're', 'openssl')
    if ($runtime -notcontains [string]$c.component) {
        $toolId = "SPDXRef-Package-$($c.component)"
        if (-not (Has-Rel $toolId 'BUILD_TOOL_OF' 'SPDXRef-Package-omnix-voice-sdk')) {
            Fail "Missing $toolId BUILD_TOOL_OF omnix-voice-sdk"
        }
    }
}

# No false current deps (planned-but-absent)
foreach ($p in $packages) {
    $n = ([string]$p.name).ToLowerInvariant()
    foreach ($bad in @('libopus', 'opus', 'react-native', 'react_native')) {
        if ($n -eq $bad -or $n.Contains($bad)) {
            Fail "False current dependency present: $($p.name)"
        }
    }
}

# Privacy (allow public github.com/fiecar repo URLs; block local paths / internal domains)
if ($sbomText -match '(?i)C:\\Users\\|OneDrive - |/Users/[^/\s"]+/|infomedia\.co\.id|BEGIN (RSA |OPENSSH )?PRIVATE KEY') {
    Fail 'SBOM contains local path / credential-like content'
}

Write-Host "verify-sbom: OK (spdx=$($sbom.spdxVersion) packages=$($packages.Count))"
exit 0
