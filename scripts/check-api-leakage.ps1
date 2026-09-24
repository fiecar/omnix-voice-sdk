#Requires -Version 7.0
<#
.SYNOPSIS
  Fail if public Omnix headers/APIs leak Baresip or re types (Issue #1 §12).
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Fail([string]$Message) {
    [Console]::Error.WriteLine("check-api-leakage: $Message")
    exit 1
}

if (-not $RepoRoot) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

$publicHeaders = @(
    (Join-Path $RepoRoot 'cpp/include/omnix_voice/omnix_voice.h'),
    (Join-Path $RepoRoot 'cpp/include/omnix_voice/omnix_types.h')
)

foreach ($h in $publicHeaders) {
    if (-not (Test-Path -LiteralPath $h)) {
        Fail "missing public header: $h"
    }
}

# Forbidden patterns in public headers
$forbidden = @(
    'baresip\.h',
    '\bre\.h\b',
    'third_party/',
    'struct\s+ua\b',
    'struct\s+call\b',
    'struct\s+account\b',
    'struct\s+config\b',
    'struct\s+mqueue\b',
    'struct\s+sa\b',
    'struct\s+pl\b',
    'struct\s+mbuf\b',
    'enum\s+ua_event',
    'enum\s+call_event',
    'enum\s+call_state',
    'enum\s+vidmode',
    'enum\s+sdp_dir',
    '\bre_',
    '\bmem_alloc\b',
    '\bmem_deref\b'
)

$failures = @()
foreach ($h in $publicHeaders) {
    $text = Get-Content -LiteralPath $h -Raw
    if ($text -match '(?i)#\s*include\s*[<"]baresip\.h[>"]') {
        $failures += "${h}: includes baresip.h"
    }
    if ($text -match '(?i)#\s*include\s*[<"]re\.h[>"]') {
        $failures += "${h}: includes re.h"
    }
    foreach ($pat in $forbidden) {
        if ($text -match $pat) {
            # Allow comments that mention the rule itself
            $lines = Get-Content -LiteralPath $h
            $lineNo = 0
            foreach ($line in $lines) {
                $lineNo++
                if ($line -match $pat -and $line -notmatch 'MUST NOT|do NOT|Baresip / re types MUST NOT') {
                    $failures += "${h}:${lineNo}: matched /$pat/ -> $line"
                }
            }
        }
    }
}

# SDK-032+: public Kotlin API under com.omnix.voice (exclude internal/)
$kotlinPublicDir = Join-Path $RepoRoot 'android/src/main/java/com/omnix/voice'
$kotlinForbidden = @(
    '(?i)\bbaresip\b',
    '(?i)\bstruct\s+ua\b',
    '(?i)\bstruct\s+call\b',
    '(?i)\bstruct\s+account\b',
    '\bre_',
    '\bmem_alloc\b',
    '\bmem_deref\b',
    '\bexternal\b'
)

if (Test-Path -LiteralPath $kotlinPublicDir) {
    $ktFiles = Get-ChildItem -LiteralPath $kotlinPublicDir -Filter '*.kt' -File
    foreach ($kt in $ktFiles) {
        $lineNo = 0
        foreach ($line in (Get-Content -LiteralPath $kt.FullName)) {
            $lineNo++
            # Skip comments that document the no-leak rule
            if ($line -match 'MUST NOT|must never|Baresip/re|no `external`|No `external`') {
                continue
            }
            foreach ($pat in $kotlinForbidden) {
                if ($line -match $pat) {
                    $failures += "$($kt.FullName):${lineNo}: matched /$pat/ -> $line"
                }
            }
        }
    }
}

# SDK-040+: public Objective-C bridge headers
$objcDir = Join-Path $RepoRoot 'ios/Sources/OmnixVoiceBridge'
$objcForbidden = @(
    '(?i)baresip\.h',
    '(?i)\bre\.h\b',
    '(?i)\bstruct\s+ua\b',
    '(?i)\bstruct\s+call\b',
    '(?i)\bstruct\s+account\b',
    '(?i)\bstruct\s+mqueue\b',
    '(?i)\benum\s+ua_event',
    '\bmem_alloc\b',
    '\bmem_deref\b'
)

if (Test-Path -LiteralPath $objcDir) {
    $hFiles = Get-ChildItem -LiteralPath $objcDir -Filter '*.h' -File
    foreach ($h in $hFiles) {
        $text = Get-Content -LiteralPath $h.FullName -Raw
        if ($text -match '(?i)#\s*include\s*[<"]baresip\.h[>"]') {
            $failures += "$($h.FullName): includes baresip.h"
        }
        if ($text -match '(?i)#\s*include\s*[<"]re\.h[>"]') {
            $failures += "$($h.FullName): includes re.h"
        }
        $lineNo = 0
        foreach ($line in (Get-Content -LiteralPath $h.FullName)) {
            $lineNo++
            if ($line -match 'MUST NOT|must not|Baresip/re|no Baresip') {
                continue
            }
            foreach ($pat in $objcForbidden) {
                if ($line -match $pat) {
                    $failures += "$($h.FullName):${lineNo}: matched /$pat/ -> $line"
                }
            }
        }
    }
}

# SDK-041+: public Swift API
$swiftDir = Join-Path $RepoRoot 'ios/Sources/OmnixVoice'
$swiftForbiddenAll = @(
    '(?i)\bbaresip\b',
    '(?i)\bstruct\s+ua\b',
    '(?i)\bstruct\s+call\b',
    '(?i)\bstruct\s+account\b',
    '\bmem_alloc\b',
    '\bmem_deref\b'
)
$swiftForbiddenPublicOnly = @(
    'OmnixVoiceBridge',
    'OmnixBridge',
    '\bNSError\b',
    '\bNSObject\b'
)

if (Test-Path -LiteralPath $swiftDir) {
    $swFiles = Get-ChildItem -LiteralPath $swiftDir -Filter '*.swift' -File
    foreach ($sw in $swFiles) {
        $lineNo = 0
        foreach ($line in (Get-Content -LiteralPath $sw.FullName)) {
            $lineNo++
            if ($line -match 'MUST NOT|must never|Baresip/re|no ObjC|No ObjC|no Baresip|wrapping ObjC|ObjC bridge') {
                continue
            }
            foreach ($pat in $swiftForbiddenAll) {
                if ($line -match $pat) {
                    $failures += "$($sw.FullName):${lineNo}: matched /$pat/ -> $line"
                }
            }
            if ($sw.Name -ne 'OmnixVoice.swift') {
                foreach ($pat in $swiftForbiddenPublicOnly) {
                    if ($line -match $pat) {
                        $failures += "$($sw.FullName):${lineNo}: matched /$pat/ -> $line"
                    }
                }
            }
        }
    }
}

# SDK-043+: packaging umbrella headers
$packDir = Join-Path $RepoRoot 'ios/packaging'
if (Test-Path -LiteralPath $packDir) {
    $packHeaders = Get-ChildItem -LiteralPath $packDir -Filter '*.h' -File -ErrorAction SilentlyContinue
    foreach ($h in $packHeaders) {
        $lineNo = 0
        foreach ($line in (Get-Content -LiteralPath $h.FullName)) {
            $lineNo++
            if ($line -match '(?i)baresip\.h|#\s*include\s*[<"]re\.h|struct\s+ua\b|third_party/') {
                $failures += "$($h.FullName):${lineNo}: packaging header leakage -> $line"
            }
        }
    }
}

if ($failures.Count -gt 0) {
    Write-Host "check-api-leakage: FAIL"
    $failures | ForEach-Object { Write-Host "  $_" }
    exit 1
}

Write-Host "check-api-leakage: PASS"
exit 0
