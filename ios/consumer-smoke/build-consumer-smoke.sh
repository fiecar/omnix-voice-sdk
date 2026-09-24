#!/usr/bin/env bash
# SDK-043 — minimal consumer compile/link against OmnixVoiceSDK.xcframework.
# [MACOS REQUIRED]
# Proves a separate target can `import OmnixVoiceSDK` and link. No SIP E2E.
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

SIM_FW="$(find "$XCF" -path '*simulator*' -name 'OmnixVoiceSDK.framework' | head -n 1 || true)"
[[ -n "$SIM_FW" ]] || fail "could not locate simulator OmnixVoiceSDK.framework inside XCFramework"
SIM_PARENT="$(dirname "$SIM_FW")"

echo "consumer-smoke: compile main.swift (-F $SIM_PARENT)"
xcrun -sdk iphonesimulator swiftc \
  -target "$TARGET" \
  -sdk "$SDK_PATH" \
  -F "$SIM_PARENT" \
  -framework OmnixVoiceSDK \
  -emit-executable \
  -o "$OUT/OmnixConsumerSmoke" \
  "$SRC/main.swift" \
  -Xlinker -rpath -Xlinker "$SIM_PARENT"

[[ -f "$OUT/OmnixConsumerSmoke" ]] || fail "consumer executable not produced"
echo "consumer-smoke: PASS (compile/link)"
ls -la "$OUT/OmnixConsumerSmoke"
