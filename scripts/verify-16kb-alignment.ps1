#Requires -Version 7.0
<#
.SYNOPSIS
  SDK-038 — Windows 16 KB page-size check for every .so in an AAR.
  Semantics match scripts/verify-16kb-alignment.sh.
  Tool: llvm-readelf.exe from the pinned NDK (not system readelf).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Aar,
    [string]$Allow = 'android/shipped-native-libs.txt',
    [string]$ReadElf = ''
)

$ErrorActionPreference = 'Stop'

function Convert-HexToken([string]$Token) {
    $t = $Token.Trim()
    if ($t.StartsWith('0x') -or $t.StartsWith('0X')) {
        $t = $t.Substring(2)
    }
    return [Convert]::ToInt64($t, 16)
}

if (-not (Test-Path -LiteralPath $Aar)) {
    Write-Output "FAIL: AAR not found: $Aar"
    exit 1
}
if (-not (Test-Path -LiteralPath $Allow)) {
    Write-Output "FAIL: allowlist not found: $Allow"
    exit 1
}

if ([string]::IsNullOrWhiteSpace($ReadElf)) {
    $ndk = $env:ANDROID_NDK_HOME
    if ([string]::IsNullOrWhiteSpace($ndk)) {
        Write-Output "FAIL: ANDROID_NDK_HOME is not set (need pinned NDK llvm-readelf)"
        exit 1
    }
    $ReadElf = Join-Path $ndk 'toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-readelf.exe'
}
if (-not (Test-Path -LiteralPath $ReadElf)) {
    Write-Output "FAIL: llvm-readelf not found: $ReadElf"
    exit 1
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
New-Item -ItemType Directory $tmp | Out-Null
try {
    tar -xf $Aar -C $tmp
    if ($LASTEXITCODE) { throw "cannot extract $Aar" }

    $allow = @(Get-Content -LiteralPath $Allow | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $sos = @(Get-ChildItem -LiteralPath $tmp -Recurse -File -Filter '*.so')
    if (-not $sos -or $sos.Count -eq 0) {
        Write-Output "FAIL: no .so in $Aar"
        exit 1
    }

    $failed = $false
    foreach ($abi in 'arm64-v8a', 'armeabi-v7a', 'x86_64') {
        foreach ($lib in $allow) {
            $path = Join-Path $tmp "jni/$abi/$lib"
            if (-not (Test-Path -LiteralPath $path)) {
                Write-Output "FAIL: missing jni/$abi/$lib"
                $failed = $true
            }
        }
    }

    foreach ($so in $sos) {
        $rel = [IO.Path]::GetRelativePath($tmp, $so.FullName).Replace('\', '/')
        $abi = Split-Path (Split-Path $so.FullName -Parent) -Leaf
        if ($rel -ne "jni/$abi/$($so.Name)" -or ($allow -notcontains $so.Name)) {
            Write-Output "FAIL: unexpected native library $rel"
            $failed = $true
            continue
        }

        $hdrs = & $ReadElf -lW $so.FullName
        $bad = $false
        $loads = @($hdrs | Where-Object { $_ -match '^\s*LOAD\s' })
        if ($loads.Count -eq 0) { $bad = $true }
        foreach ($l in $loads) {
            $tok = ($l.Trim() -split '\s+')[-1]
            $v = Convert-HexToken $tok
            if ($v -lt 16384 -or ($v -band ($v - 1)) -ne 0) { $bad = $true }
        }

        $relro = @($hdrs | Where-Object { $_ -match '^\s*GNU_RELRO\s' } | Select-Object -First 1)
        if ($relro.Count -gt 0) {
            $t = $relro[0].Trim() -split '\s+'
            # Type Offset VirtAddr PhysAddr FileSiz MemSiz Flg Align
            $end = (Convert-HexToken $t[2]) + (Convert-HexToken $t[5])
            if (($end % 16384) -ne 0) {
                Write-Output "RELRO-CHECK: $rel end not 16 KB aligned"
                $bad = $true
            }
        }

        if ($bad) {
            if ($abi -eq 'armeabi-v7a') {
                Write-Output "WARN (32-bit, informational): $rel"
            }
            else {
                Write-Output "FAIL: $rel"
                $failed = $true
            }
        }
        else {
            Write-Output "OK: $rel"
        }
    }

    if ($failed) {
        Write-Output "ERROR: 16 KB check FAILED (see https://developer.android.com/guide/practices/page-sizes)"
        exit 1
    }
    Write-Output "SUCCESS: all shipped 64-bit .so are 16 KB compatible"
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
