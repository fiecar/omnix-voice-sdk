#!/usr/bin/env bash
# SDK-043 — validate OmnixVoiceSDK.xcframework (static-library layout).
# [MACOS REQUIRED] for lipo; structural checks otherwise portable.
set -euo pipefail

fail() { echo "verify-xcframework: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCF="${1:-$ROOT/dist/OmnixVoiceSDK.xcframework}"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION" 2>/dev/null || echo "0.1.0")"

[[ -d "$XCF" ]] || fail "missing XCFramework at $XCF"
[[ -f "$XCF/Info.plist" ]] || fail "missing Info.plist"

echo "verify-xcframework: inspecting $XCF"

DEVICE_LIB="$(find "$XCF" -path '*ios-arm64*' -name 'libOmnixVoice.a' | head -n 1 || true)"
SIM_LIB="$(find "$XCF" -path '*simulator*' -name 'libOmnixVoice.a' | head -n 1 || true)"
[[ -n "$DEVICE_LIB" ]] || fail "missing ios-arm64 libOmnixVoice.a"
[[ -n "$SIM_LIB" ]] || fail "missing ios-arm64-simulator libOmnixVoice.a"
echo "OK: device library = $DEVICE_LIB"
echo "OK: simulator library = $SIM_LIB"

for lib in "$DEVICE_LIB" "$SIM_LIB"; do
  hdr_dir="$(dirname "$lib")/Headers"
  # create-xcframework may place Headers next to the library
  if [[ ! -d "$hdr_dir" ]]; then
    hdr_dir="$(find "$(dirname "$lib")" -type d -name Headers | head -n 1 || true)"
  fi
  [[ -d "$hdr_dir" ]] || fail "missing Headers next to $lib"
  [[ -f "$hdr_dir/OmnixVoiceSDK.h" ]] || fail "missing umbrella in $hdr_dir"
  [[ -f "$hdr_dir/OmnixVoiceBridge.h" ]] || fail "missing OmnixVoiceBridge.h in $hdr_dir"
  [[ -f "$hdr_dir/module.modulemap" ]] || fail "missing module.modulemap in $hdr_dir"

  if grep -Eiq '^\s*#\s*include\s*[<"]baresip\.h[>"]' "$hdr_dir"/*.h; then
    fail "public headers include baresip.h"
  fi
  if grep -Eiq '^\s*#\s*include\s*[<"]re\.h[>"]' "$hdr_dir"/*.h; then
    fail "public headers include re.h"
  fi
  if find "$hdr_dir" \( -iname '*baresip*' -o -iname 're.h' \) | grep -q .; then
    fail "baresip/re headers packaged"
  fi

  if command -v lipo >/dev/null; then
    archs="$(lipo -archs "$lib")"
    echo "archs ($lib): $archs"
    echo "$archs" | grep -qw arm64 || fail "arm64 missing in $lib"
  fi

  if grep -R "fieca\|OneDrive\|infomedia\.co\.id\|C:\\\\Users" "$hdr_dir" 2>/dev/null; then
    fail "local developer path leak in headers"
  fi
done

if command -v plutil >/dev/null; then
  plutil -p "$XCF/Info.plist" | tee "$ROOT/build/xcframework-info.txt" || true
  if ! plutil -p "$XCF/Info.plist" | grep -qi 'ios'; then
    fail "Info.plist does not mention ios"
  fi
fi

ZIP="$ROOT/dist/OmnixVoiceSDK-${VERSION}.xcframework.zip"
if [[ -f "$ZIP" ]]; then
  if command -v shasum >/dev/null; then
    got="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
    echo "SHA-256 ($ZIP) = $got"
    if [[ -f "${ZIP}.sha256" ]]; then
      exp="$(awk '{print $1}' "${ZIP}.sha256")"
      [[ "$got" == "$exp" ]] || fail "SHA-256 mismatch for zip"
      echo "OK: zip checksum matches"
    fi
  fi
fi

[[ -f "$ROOT/dist/THIRD_PARTY_NOTICES.md" ]] \
  || fail "dist/THIRD_PARTY_NOTICES.md missing"

echo "verify-xcframework: PASS"
