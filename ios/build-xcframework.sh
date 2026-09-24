#!/usr/bin/env bash
# SDK-043 — build OmnixVoiceSDK.xcframework (device arm64 + simulator arm64).
# [MACOS REQUIRED]
#
# Issue #2 packaging model:
#   xcodebuild -create-xcframework -library … -headers …
#
# Public module OmnixVoiceSDK exposes Omnix ObjC bridge headers only.
# Native stack (omnix_voice, baresip, re, OpenSSL) + ObjC bridge are folded into
# libOmnixVoice.a per slice. Swift facade remains source under ios/Sources/OmnixVoice
# until ObjC is a clang submodule (required for BUILD_LIBRARY_FOR_DISTRIBUTION /
# .swiftinterface — unsupported with bridging headers on Xcode 15+).
#
# Release-oriented (-O2); unsigned; Bitcode OFF; iOS 15.0.
set -euo pipefail

fail() { echo "build-xcframework: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION" 2>/dev/null || echo "0.1.0")"
MIN_IOS="${DEPLOYMENT_TARGET:-15.0}"
DIST="${DIST_DIR:-$ROOT/dist}"
WORK="${WORK_DIR:-$ROOT/build/xcframework}"
PACK="$ROOT/ios/packaging"
BRIDGE_SRC="$ROOT/ios/Sources/OmnixVoiceBridge"
OPENSSL_ROOT_BASE="${OPENSSL_ROOT_BASE:-$ROOT/build/openssl-ios}"

[[ "$(uname -s)" == "Darwin" ]] || fail "must run on macOS [MACOS REQUIRED]"
[[ -f "$PACK/OmnixVoiceSDK.h" ]] || fail "missing packaging umbrella header"
[[ -f "$BRIDGE_SRC/OmnixVoiceBridge.h" ]] || fail "missing OmnixVoiceBridge.h (SDK-040)"
[[ -f "$ROOT/ios/build-ios.sh" ]] || fail "missing ios/build-ios.sh (SDK-039)"

echo "build-xcframework: VERSION=$VERSION MIN_IOS=$MIN_IOS (static-library XCFramework)"

chmod +x "$ROOT/scripts/verify-third-party.sh" \
  "$ROOT/scripts/build-openssl-ios.sh" \
  "$ROOT/ios/build-ios.sh" \
  "$ROOT/scripts/check-api-leakage.sh"

"$ROOT/scripts/verify-third-party.sh"
"$ROOT/scripts/check-api-leakage.sh"

if [[ ! -f "$OPENSSL_ROOT_BASE/iphoneos-arm64/lib/libssl.a" ]]; then
  "$ROOT/scripts/build-openssl-ios.sh"
fi

"$ROOT/ios/build-ios.sh"
[[ -f "$ROOT/build/ios-device/libomnix_voice.a" ]] || fail "missing device libomnix_voice.a"
[[ -f "$ROOT/build/ios-sim/libomnix_voice.a" ]] || fail "missing sim libomnix_voice.a"

rm -rf "$WORK" "$DIST/OmnixVoiceSDK.xcframework"
mkdir -p "$WORK" "$DIST"

stage_headers() {
  local dest="$1"
  mkdir -p "$dest"
  cp -f "$PACK/OmnixVoiceSDK.h" "$dest/OmnixVoiceSDK.h"
  cp -f "$BRIDGE_SRC/OmnixVoiceBridge.h" "$dest/OmnixVoiceBridge.h"
  # Clang module map for `import OmnixVoiceSDK` / @import OmnixVoiceSDK
  cat > "$dest/module.modulemap" <<'EOF'
module OmnixVoiceSDK {
  umbrella header "OmnixVoiceSDK.h"
  export *
  module * { export * }
}
EOF
  if grep -Eiq '^\s*#\s*include\s*[<"]baresip\.h[>"]' "$dest"/*.h; then
    fail "staged public headers must not #include baresip.h"
  fi
  if grep -Eiq '^\s*#\s*include\s*[<"]re\.h[>"]' "$dest"/*.h; then
    fail "staged public headers must not #include re.h"
  fi
  if grep -En 'struct[[:space:]]+ua\b|struct[[:space:]]+call\b|struct[[:space:]]+account\b|third_party/' \
    "$dest"/*.h | grep -Ev 'MUST NOT|must not|Baresip/re|no Baresip|Never includes' >/dev/null; then
    fail "staged public headers must not declare Baresip/re types or third_party paths"
  fi
}

build_static_slice() {
  local sdk="$1"
  local native_dir="$2"
  local openssl_slice="$3"
  local out_lib="$4"
  local headers_out="$5"

  local sdk_path
  sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
  [[ -d "$sdk_path" ]] || fail "SDK not found: $sdk"

  local min_flag
  if [[ "$sdk" == "iphonesimulator" ]]; then
    min_flag="-mios-simulator-version-min=$MIN_IOS"
  else
    min_flag="-miphoneos-version-min=$MIN_IOS"
  fi

  local slice_work="$WORK/$sdk"
  rm -rf "$slice_work"
  mkdir -p "$slice_work/obj" "$headers_out"

  stage_headers "$headers_out"

  local openssl_root="$OPENSSL_ROOT_BASE/$openssl_slice"
  [[ -f "$openssl_root/lib/libssl.a" ]] || fail "missing OpenSSL at $openssl_root"

  echo "build-xcframework: compile OmnixVoiceBridge.m ($sdk arm64)"
  xcrun -sdk "$sdk" clang -c \
    -arch arm64 \
    -isysroot "$sdk_path" \
    $min_flag \
    -fobjc-arc \
    -fmodules \
    -fvisibility=hidden \
    -O2 \
    -DNDEBUG \
    -Wall -Wextra -Werror \
    -I "$ROOT/cpp/include" \
    -I "$BRIDGE_SRC" \
    "$BRIDGE_SRC/OmnixVoiceBridge.m" \
    -o "$slice_work/obj/OmnixVoiceBridge.o"

  # Issue #2 name: libOmnixVoice.a — merge native + OpenSSL + ObjC.
  # Apple `ar -x` silently keeps only one member per basename; extract each
  # member via `ar -p` into a uniquely named object file.
  local merge_dir="$slice_work/merge"
  rm -rf "$merge_dir"
  mkdir -p "$merge_dir"
  local idx=0
  for archive in \
    "$native_dir/libomnix_voice.a" \
    "$native_dir/libbaresip.a" \
    "$native_dir/libre.a" \
    "$openssl_root/lib/libssl.a" \
    "$openssl_root/lib/libcrypto.a"
  do
    [[ -f "$archive" ]] || fail "missing $archive"
    idx=$((idx + 1))
    local sub="$merge_dir/$idx"
    mkdir -p "$sub"
    local member safe n=0
    while IFS= read -r member; do
      [[ -n "$member" ]] || continue
      n=$((n + 1))
      safe="$(printf '%s' "$member" | tr '/ ' '__')"
      ar -p "$archive" "$member" > "$sub/${idx}_${n}_${safe}"
    done < <(ar -t "$archive")
    [[ "$n" -gt 0 ]] || fail "no members extracted from $archive"
    echo "build-xcframework: extracted $n objects from $(basename "$archive")"
  done
  cp -f "$slice_work/obj/OmnixVoiceBridge.o" "$merge_dir/OmnixVoiceBridge.o"
  rm -f "$out_lib"
  # shellcheck disable=SC2046
  ar -rcs "$out_lib" $(find "$merge_dir" -type f | sort)
  [[ -f "$out_lib" ]] || fail "failed to produce $out_lib"
  # Sanity: Omnix + a known re symbol should be present
  if command -v nm >/dev/null; then
    nm "$out_lib" 2>/dev/null | grep -q 'omnix_init\|T _omnix_init' \
      || echo "build-xcframework: WARN — omnix_init not found via nm"
  fi
  echo "build-xcframework: wrote $out_lib"
}

DEVICE_LIB="$WORK/ios-arm64/libOmnixVoice.a"
SIM_LIB="$WORK/ios-arm64-simulator/libOmnixVoice.a"
DEVICE_HDR="$WORK/ios-arm64/Headers"
SIM_HDR="$WORK/ios-arm64-simulator/Headers"
mkdir -p "$(dirname "$DEVICE_LIB")" "$(dirname "$SIM_LIB")"

build_static_slice "iphoneos" \
  "$ROOT/build/ios-device" \
  "iphoneos-arm64" \
  "$DEVICE_LIB" \
  "$DEVICE_HDR"

build_static_slice "iphonesimulator" \
  "$ROOT/build/ios-sim" \
  "iphonesimulator-arm64" \
  "$SIM_LIB" \
  "$SIM_HDR"

echo "build-xcframework: xcodebuild -create-xcframework"
rm -rf "$DIST/OmnixVoiceSDK.xcframework"
xcodebuild -create-xcframework \
  -library "$DEVICE_LIB" -headers "$DEVICE_HDR" \
  -library "$SIM_LIB" -headers "$SIM_HDR" \
  -output "$DIST/OmnixVoiceSDK.xcframework"

[[ -d "$DIST/OmnixVoiceSDK.xcframework" ]] || fail "XCFramework not produced"

cp -f "$ROOT/THIRD_PARTY_NOTICES.md" "$DIST/THIRD_PARTY_NOTICES.md"
if [[ -d "$ROOT/LICENSES" ]]; then
  rm -rf "$DIST/LICENSES"
  cp -R "$ROOT/LICENSES" "$DIST/LICENSES"
fi

ZIP_NAME="OmnixVoiceSDK-${VERSION}.xcframework.zip"
rm -f "$DIST/$ZIP_NAME" "$DIST/${ZIP_NAME}.sha256"
(cd "$DIST" && ditto -c -k --keepParent OmnixVoiceSDK.xcframework "$ZIP_NAME")
(
  cd "$DIST"
  shasum -a 256 "$ZIP_NAME" | tee "${ZIP_NAME}.sha256"
)

echo "build-xcframework: SUCCESS"
ls -la "$DIST/OmnixVoiceSDK.xcframework" "$DIST/$ZIP_NAME"
