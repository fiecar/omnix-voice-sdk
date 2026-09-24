#!/usr/bin/env bash
# SDK-043 — consumer compile/link against static OmnixVoiceSDK.xcframework.
# [MACOS REQUIRED]
# Proves a separate target can `import OmnixVoiceSDK` (ObjC module) and link.
# No SIP E2E. Clients must also link system frameworks used by the static archive.
set -euo pipefail

fail() { echo "consumer-smoke: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
XCF="${1:-$ROOT/dist/OmnixVoiceSDK.xcframework}"
OUT="${OUT_DIR:-$ROOT/build/ios-consumer-smoke}"
MIN_IOS="${DEPLOYMENT_TARGET:-15.0}"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ "$(uname -s)" == "Darwin" ]] || fail "must run on macOS [MACOS REQUIRED]"
[[ -d "$XCF" ]] || fail "missing XCFramework at $XCF"
[[ -f "$SRC/main.swift" ]] || fail "missing main.swift"

SDK_PATH="$(xcrun --sdk iphonesimulator --show-sdk-path)"
TARGET="arm64-apple-ios${MIN_IOS}-simulator"
mkdir -p "$OUT"

SIM_LIB="$(find "$XCF" -path '*simulator*' -name 'libOmnixVoice.a' | head -n 1 || true)"
[[ -n "$SIM_LIB" ]] || fail "simulator libOmnixVoice.a not found in XCFramework"
SIM_SLICE="$(cd "$(dirname "$SIM_LIB")" && pwd)"
HDR="$SIM_SLICE/Headers"
[[ -d "$HDR" ]] || HDR="$(find "$SIM_SLICE" -type d -name Headers | head -n 1)"
[[ -d "$HDR" ]] || fail "Headers not found for simulator slice"

echo "consumer-smoke: compile main.swift against $SIM_LIB"
xcrun -sdk iphonesimulator swiftc \
  -target "$TARGET" \
  -sdk "$SDK_PATH" \
  -I "$HDR" \
  -fmodule-map-file="$HDR/module.modulemap" \
  -emit-executable \
  -o "$OUT/OmnixConsumerSmoke" \
  "$SRC/main.swift" \
  "$SIM_LIB" \
  -lresolv -lc++ -lz \
  -framework Foundation \
  -framework AVFoundation \
  -framework AudioToolbox \
  -framework CoreAudio \
  -framework Security \
  -framework SystemConfiguration \
  -framework CFNetwork \
  -framework CoreMedia \
  -framework UIKit

[[ -f "$OUT/OmnixConsumerSmoke" ]] || fail "consumer executable not produced"
echo "consumer-smoke: PASS (compile/link)"
ls -la "$OUT/OmnixConsumerSmoke"
