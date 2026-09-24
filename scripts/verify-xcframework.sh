#!/usr/bin/env bash
# SDK-043 — validate OmnixVoiceSDK.xcframework structure + public API leakage.
# [MACOS REQUIRED] for full lipo/otool checks; structural checks are portable.
set -euo pipefail

fail() { echo "verify-xcframework: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCF="${1:-$ROOT/dist/OmnixVoiceSDK.xcframework}"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION" 2>/dev/null || echo "0.1.0")"

[[ -d "$XCF" ]] || fail "missing XCFramework at $XCF"
[[ -f "$XCF/Info.plist" ]] || fail "missing Info.plist"

echo "verify-xcframework: inspecting $XCF"

# Expected library slices (framework layout from create-xcframework).
DEVICE_FW=""
SIM_FW=""
while IFS= read -r -d '' fw; do
  rel="${fw#$XCF/}"
  case "$rel" in
    ios-arm64/*|ios-arm64_*)
      DEVICE_FW="$fw"
      ;;
    ios-arm64-simulator/*|ios-arm64_x86_64-simulator/*|*simulator*)
      SIM_FW="$fw"
      ;;
  esac
done < <(find "$XCF" -name 'OmnixVoiceSDK.framework' -print0)

# Fallback: walk Info.plist AvailableLibraries via plutil if find missed.
if [[ -z "$DEVICE_FW" || -z "$SIM_FW" ]]; then
  if command -v plutil >/dev/null; then
    echo "verify-xcframework: AvailableLibraries:"
    plutil -p "$XCF/Info.plist" || true
  fi
  # Accept either nested framework path naming from xcodebuild
  DEVICE_FW="$(find "$XCF" -path '*ios-arm64*' -name 'OmnixVoiceSDK.framework' | head -n 1 || true)"
  SIM_FW="$(find "$XCF" -path '*simulator*' -name 'OmnixVoiceSDK.framework' | head -n 1 || true)"
fi

[[ -n "$DEVICE_FW" ]] || fail "missing ios-arm64 framework slice"
[[ -n "$SIM_FW" ]] || fail "missing ios-arm64-simulator framework slice"
echo "OK: device framework = $DEVICE_FW"
echo "OK: simulator framework = $SIM_FW"

for fw in "$DEVICE_FW" "$SIM_FW"; do
  [[ -f "$fw/OmnixVoiceSDK" ]] || fail "missing binary in $fw"
  [[ -f "$fw/Headers/OmnixVoiceSDK.h" ]] || fail "missing umbrella header in $fw"
  [[ -f "$fw/Headers/OmnixVoiceBridge.h" ]] || fail "missing OmnixVoiceBridge.h in $fw"
  [[ -f "$fw/Modules/module.modulemap" ]] || fail "missing module.modulemap in $fw"
  [[ -f "$fw/Info.plist" ]] || fail "missing framework Info.plist in $fw"

  # Public header leakage (real includes / types — not documentary comments)
  if grep -Eiq '^\s*#\s*include\s*[<"]baresip\.h[>"]' "$fw/Headers/"*.h; then
    fail "public headers in $fw include baresip.h"
  fi
  if grep -Eiq '^\s*#\s*include\s*[<"]re\.h[>"]' "$fw/Headers/"*.h; then
    fail "public headers in $fw include re.h"
  fi
  if grep -En 'struct[[:space:]]+ua\b|struct[[:space:]]+call\b|struct[[:space:]]+account\b|third_party/' \
    "$fw/Headers/"*.h | grep -Ev 'MUST NOT|must not|Baresip/re|no Baresip|Never includes' >/dev/null; then
    fail "public headers in $fw leak Baresip/re/third_party"
  fi
  # Ensure no third_party headers were packaged
  if find "$fw" \( -iname '*baresip*' -o -iname 're.h' \) | grep -q .; then
    fail "baresip/re artifacts found inside $fw"
  fi

  # Deployment target
  if command -v plutil >/dev/null; then
    min_os="$(plutil -extract MinimumOSVersion raw "$fw/Info.plist" 2>/dev/null || true)"
    if [[ -n "$min_os" && "$min_os" != "15.0" ]]; then
      fail "MinimumOSVersion must be 15.0 (got $min_os)"
    fi
  fi

  # Architecture (macOS)
  if command -v lipo >/dev/null; then
    archs="$(lipo -archs "$fw/OmnixVoiceSDK")"
    echo "archs ($fw): $archs"
    echo "$archs" | grep -qw arm64 || fail "arm64 missing in $fw"
  fi

  # No local developer path leaks in plist / modulemap (text metadata only)
  if grep -R "fieca\|OneDrive\|infomedia\.co\.id\|C:\\\\Users" "$fw/Info.plist" "$fw/Modules" "$fw/Headers" 2>/dev/null; then
    fail "local developer path leak in framework metadata"
  fi
done

# XCFramework Info.plist platform sanity
if command -v plutil >/dev/null; then
  plutil -p "$XCF/Info.plist" | tee "$ROOT/build/xcframework-info.txt" || true
  if ! plutil -p "$XCF/Info.plist" | grep -q 'ios'; then
    fail "Info.plist does not mention ios platform"
  fi
fi

# Zip + checksum if present
ZIP="$ROOT/dist/OmnixVoiceSDK-${VERSION}.xcframework.zip"
if [[ -f "$ZIP" ]]; then
  if command -v shasum >/dev/null; then
    got="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
    echo "SHA-256 ($ZIP) = $got"
    if [[ -f "${ZIP}.sha256" ]]; then
      exp="$(awk '{print $1}' "${ZIP}.sha256")"
      [[ "$got" == "$exp" ]] || fail "SHA-256 mismatch for zip"
      echo "OK: zip checksum matches ${ZIP}.sha256"
    fi
  fi
else
  echo "WARN: zip not found at $ZIP (optional at verify time)"
fi

# Attribution companions for distribution
[[ -f "$ROOT/dist/THIRD_PARTY_NOTICES.md" ]] \
  || fail "dist/THIRD_PARTY_NOTICES.md missing (required with binary distribution)"

echo "verify-xcframework: PASS"
