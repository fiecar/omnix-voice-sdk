#!/usr/bin/env bash
# SDK-041 — typecheck / compile public Swift facade against ObjC bridge.
# [MACOS REQUIRED]
# Verifies Issue #1 §20A names build without warnings. No SIP E2E.
set -euo pipefail

fail() { echo "build-ios-swift: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_SRC="$ROOT/ios/Sources/OmnixVoice"
BRIDGE_SRC="$ROOT/ios/Sources/OmnixVoiceBridge"
OUT="${OUT_DIR:-$ROOT/build/ios-swift}"
MIN_IOS="${DEPLOYMENT_TARGET:-15.0}"
BRIDGING_HEADER="$SWIFT_SRC/OmnixVoice-Bridging-Header.h"

[[ "$(uname -s)" == "Darwin" ]] || fail "must run on macOS"
[[ -f "$BRIDGING_HEADER" ]] || fail "missing bridging header"
[[ -f "$BRIDGE_SRC/OmnixVoiceBridge.h" ]] || fail "missing OmnixVoiceBridge.h (SDK-040)"

# Ensure ObjC bridge object exists (headers alone are enough for -typecheck,
# but we also emit a module after compiling the bridge .o for a stronger gate).
chmod +x "$ROOT/ios/build-ios-bridge.sh"
"$ROOT/ios/build-ios-bridge.sh"

SDK_PATH="$(xcrun --sdk iphonesimulator --show-sdk-path)"
TARGET="arm64-apple-ios${MIN_IOS}-simulator"
mkdir -p "$OUT"

# Prefer stable glob order; bash 3.2 compatible (macOS).
# shellcheck disable=SC2206
SWIFT_FILES=("$SWIFT_SRC"/*.swift)
[[ -f "${SWIFT_FILES[0]:-}" ]] || fail "no Swift sources under $SWIFT_SRC"

echo "build-ios-swift: typecheck ${#SWIFT_FILES[@]} Swift files (warnings as errors)"
# -warnings-as-errors ensures "Builds without warnings"
xcrun -sdk iphonesimulator swiftc -typecheck \
  -target "$TARGET" \
  -sdk "$SDK_PATH" \
  -import-objc-header "$BRIDGING_HEADER" \
  -I "$BRIDGE_SRC" \
  -I "$ROOT/cpp/include" \
  -parse-as-library \
  -warnings-as-errors \
  "${SWIFT_FILES[@]}"

echo "build-ios-swift: emit library (link ObjC bridge .o; C facade unresolved OK via -undefined dynamic_lookup for compile gate)"
# Produce a linkable dylib for CI artifact evidence. Native C symbols resolve at
# final XCFramework link (SDK-043). For this gate we allow undefined omnix_*.
xcrun -sdk iphonesimulator swiftc \
  -target "$TARGET" \
  -sdk "$SDK_PATH" \
  -import-objc-header "$BRIDGING_HEADER" \
  -I "$BRIDGE_SRC" \
  -I "$ROOT/cpp/include" \
  -parse-as-library \
  -warnings-as-errors \
  -emit-library \
  -emit-module \
  -module-name OmnixVoice \
  -o "$OUT/libOmnixVoice.dylib" \
  -Xlinker -undefined -Xlinker dynamic_lookup \
  "${SWIFT_FILES[@]}" \
  "$ROOT/build/ios-bridge/OmnixVoiceBridge.o" \
  -framework Foundation

echo "build-ios-swift: SUCCESS"
ls -la "$OUT/libOmnixVoice.dylib"
