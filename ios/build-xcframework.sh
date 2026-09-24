#!/usr/bin/env bash
# SDK-043 — build OmnixVoiceSDK.xcframework (device arm64 + simulator arm64).
# [MACOS REQUIRED]
#
# Packages a dynamic framework per slice containing:
#   - Native static stack (omnix_voice, baresip, re, OpenSSL) force-loaded
#   - Objective-C bridge
#   - Public Swift facade (module name OmnixVoiceSDK)
#
# Public headers: Omnix umbrella + OmnixVoiceBridge only (never third_party/).
# Release-oriented (-O2 / -O); unsigned (no customer signing identity).
# Swift binary interface: -enable-library-evolution (+ .swiftinterface)
#   == Xcode BUILD_LIBRARY_FOR_DISTRIBUTION=YES.
set -euo pipefail

fail() { echo "build-xcframework: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION" 2>/dev/null || echo "0.1.0")"
MIN_IOS="${DEPLOYMENT_TARGET:-15.0}"
DIST="${DIST_DIR:-$ROOT/dist}"
WORK="${WORK_DIR:-$ROOT/build/xcframework}"
PACK="$ROOT/ios/packaging"
BRIDGE_SRC="$ROOT/ios/Sources/OmnixVoiceBridge"
SWIFT_SRC="$ROOT/ios/Sources/OmnixVoice"
OPENSSL_ROOT_BASE="${OPENSSL_ROOT_BASE:-$ROOT/build/openssl-ios}"

[[ "$(uname -s)" == "Darwin" ]] || fail "must run on macOS [MACOS REQUIRED]"
[[ -f "$PACK/OmnixVoiceSDK.h" ]] || fail "missing packaging umbrella header"
[[ -f "$BRIDGE_SRC/OmnixVoiceBridge.h" ]] || fail "missing OmnixVoiceBridge.h (SDK-040)"
[[ -f "$ROOT/ios/build-ios.sh" ]] || fail "missing ios/build-ios.sh (SDK-039)"

echo "build-xcframework: VERSION=$VERSION MIN_IOS=$MIN_IOS"

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
  # Fail on real includes / type decls — not documentary "MUST NOT … baresip.h" comments.
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

merge_native_static() {
  local out="$1"
  shift
  local inputs=("$@")
  for f in "${inputs[@]}"; do
    [[ -f "$f" ]] || fail "missing static input: $f"
  done
  rm -f "$out"
  libtool -static -o "$out" "${inputs[@]}"
  [[ -f "$out" ]] || fail "libtool failed to produce $out"
}

build_slice() {
  local sdk="$1"
  local triple="$2"
  local native_dir="$3"
  local openssl_slice="$4"
  local framework_out="$5"

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
  mkdir -p "$slice_work/obj" "$slice_work/Headers" "$slice_work/Modules/OmnixVoiceSDK.swiftmodule"

  stage_headers "$slice_work/Headers"
  cp -f "$PACK/module.modulemap" "$slice_work/Modules/module.modulemap"

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

  # Issue #2 combined archive name (for inspection / alternate -library packaging).
  # Do NOT force_load the merged archive alone — Apple libtool drops duplicate
  # member names across libre/libbaresip. Link each archive with -force_load.
  merge_native_static "$slice_work/libOmnixVoice.a" \
    "$native_dir/libomnix_voice.a" \
    "$native_dir/libbaresip.a" \
    "$native_dir/libre.a" \
    "$openssl_root/lib/libssl.a" \
    "$openssl_root/lib/libcrypto.a" \
    "$slice_work/obj/OmnixVoiceBridge.o"

  local bridging="$slice_work/Bridging.h"
  cat > "$bridging" <<'EOF'
#import "OmnixVoiceBridge.h"
EOF

  # shellcheck disable=SC2206
  local swift_files=("$SWIFT_SRC"/*.swift)
  [[ -f "${swift_files[0]:-}" ]] || fail "no Swift sources under $SWIFT_SRC"

  local mod_dir="$slice_work/Modules/OmnixVoiceSDK.swiftmodule"
  local swiftmodule_file
  if [[ "$sdk" == "iphonesimulator" ]]; then
    swiftmodule_file="$mod_dir/arm64-apple-ios${MIN_IOS}-simulator.swiftmodule"
  else
    swiftmodule_file="$mod_dir/arm64-apple-ios${MIN_IOS}.swiftmodule"
  fi

  local bin="$slice_work/OmnixVoiceSDK"
  echo "build-xcframework: link OmnixVoiceSDK framework binary ($sdk)"
  # Mixed Swift+ObjC via bridging header cannot use -enable-library-evolution /
  # -emit-module-interface. Ships .swiftmodule only (see docs/toolchain.md).
  # System libs: resolv (re DNS), AudioUnit/AudioToolbox (baresip audiounit).
  xcrun -sdk "$sdk" swiftc \
    -target "$triple" \
    -sdk "$sdk_path" \
    -import-objc-header "$bridging" \
    -I "$BRIDGE_SRC" \
    -I "$ROOT/cpp/include" \
    -parse-as-library \
    -O \
    -module-name OmnixVoiceSDK \
    -emit-module \
    -emit-module-path "$swiftmodule_file" \
    -emit-objc-header-path "$slice_work/Headers/OmnixVoiceSDK-Swift.h" \
    -emit-library \
    -o "$bin" \
    -Xlinker -install_name -Xlinker "@rpath/OmnixVoiceSDK.framework/OmnixVoiceSDK" \
    -Xlinker -force_load -Xlinker "$native_dir/libomnix_voice.a" \
    -Xlinker -force_load -Xlinker "$native_dir/libbaresip.a" \
    -Xlinker -force_load -Xlinker "$native_dir/libre.a" \
    -Xlinker -force_load -Xlinker "$openssl_root/lib/libssl.a" \
    -Xlinker -force_load -Xlinker "$openssl_root/lib/libcrypto.a" \
    "$slice_work/obj/OmnixVoiceBridge.o" \
    -lresolv \
    -lc++ \
    -lz \
    -framework Foundation \
    -framework AVFoundation \
    -framework AudioToolbox \
    -framework CoreAudio \
    -framework Security \
    -framework SystemConfiguration \
    -framework CFNetwork \
    -framework CoreMedia \
    -framework UIKit \
    "${swift_files[@]}"

  # swiftc -emit-library on Darwin often appends .dylib; framework binary must be extensionless.
  if [[ -f "${bin}.dylib" && ! -f "$bin" ]]; then
    mv "${bin}.dylib" "$bin"
  fi
  [[ -f "$bin" ]] || fail "framework binary not produced for $sdk"

  # Assemble .framework bundle
  local fw="$framework_out"
  rm -rf "$fw"
  mkdir -p "$fw/Headers" "$fw/Modules/OmnixVoiceSDK.swiftmodule"
  cp -f "$bin" "$fw/OmnixVoiceSDK"
  cp -f "$slice_work/Headers/"*.h "$fw/Headers/"
  cp -f "$PACK/module.modulemap" "$fw/Modules/module.modulemap"
  # Place swiftmodule (no .swiftinterface — bridging-header build; see toolchain.md)
  cp -R "$mod_dir/." "$fw/Modules/OmnixVoiceSDK.swiftmodule/"
  sed "s/0\\.1\\.0/${VERSION}/g" "$PACK/Info.plist" > "$fw/Info.plist"

  # Also keep Issue #2 static archive path for inspection / alternate packaging notes.
  cp -f "$slice_work/libOmnixVoice.a" "$slice_work/../libOmnixVoice-${sdk}.a"

  echo "build-xcframework: framework slice ready: $fw"
}

DEVICE_FW="$WORK/iphoneos/OmnixVoiceSDK.framework"
SIM_FW="$WORK/iphonesimulator/OmnixVoiceSDK.framework"

build_slice "iphoneos" \
  "arm64-apple-ios${MIN_IOS}" \
  "$ROOT/build/ios-device" \
  "iphoneos-arm64" \
  "$DEVICE_FW"

build_slice "iphonesimulator" \
  "arm64-apple-ios${MIN_IOS}-simulator" \
  "$ROOT/build/ios-sim" \
  "iphonesimulator-arm64" \
  "$SIM_FW"

echo "build-xcframework: xcodebuild -create-xcframework"
rm -rf "$DIST/OmnixVoiceSDK.xcframework"
xcodebuild -create-xcframework \
  -framework "$DEVICE_FW" \
  -framework "$SIM_FW" \
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
