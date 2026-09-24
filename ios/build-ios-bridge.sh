#!/usr/bin/env bash
# SDK-040 — compile Objective-C bridge against iOS simulator SDK.
# [MACOS REQUIRED]
# Does not run SIP E2E. Verifies OmnixVoiceBridge.h/.m compile with ARC
# and that the public header does not pull Baresip/re.
set -euo pipefail

fail() { echo "build-ios-bridge: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/ios/Sources/OmnixVoiceBridge"
OUT="${OUT_DIR:-$ROOT/build/ios-bridge}"
MIN_IOS="${DEPLOYMENT_TARGET:-15.0}"

[[ "$(uname -s)" == "Darwin" ]] || fail "must run on macOS"
[[ -f "$SRC/OmnixVoiceBridge.h" ]] || fail "missing OmnixVoiceBridge.h"
[[ -f "$SRC/OmnixVoiceBridge.m" ]] || fail "missing OmnixVoiceBridge.m"
[[ -f "$ROOT/cpp/include/omnix_voice/omnix_voice.h" ]] || fail "missing C facade headers"

# Public header must not #include Baresip/re (belt-and-suspenders vs check-api-leakage).
# Do not match documentary comments that mention the forbidden names.
if grep -Eiq '^\s*#\s*include\s*[<"]baresip\.h[>"]' "$SRC/OmnixVoiceBridge.h"; then
  fail "OmnixVoiceBridge.h must not #include baresip.h"
fi
if grep -Eiq '^\s*#\s*include\s*[<"]re\.h[>"]' "$SRC/OmnixVoiceBridge.h"; then
  fail "OmnixVoiceBridge.h must not #include re.h"
fi
if grep -En 'struct[[:space:]]+ua\b|struct[[:space:]]+call\b|struct[[:space:]]+account\b' \
  "$SRC/OmnixVoiceBridge.h" | grep -Ev 'MUST NOT|must not|Baresip/re|no Baresip' >/dev/null; then
  fail "OmnixVoiceBridge.h must not declare Baresip/re types"
fi

SDK_PATH="$(xcrun --sdk iphonesimulator --show-sdk-path)"
[[ -d "$SDK_PATH" ]] || fail "iphonesimulator SDK not found"

mkdir -p "$OUT"
OBJ="$OUT/OmnixVoiceBridge.o"
LIB="$OUT/libOmnixVoiceBridge.a"

echo "build-ios-bridge: compiling OmnixVoiceBridge.m (iphonesimulator arm64, iOS $MIN_IOS)"
xcrun -sdk iphonesimulator clang -c \
  -arch arm64 \
  -isysroot "$SDK_PATH" \
  -mios-simulator-version-min="$MIN_IOS" \
  -fobjc-arc \
  -fmodules \
  -Wall -Wextra -Werror \
  -I "$ROOT/cpp/include" \
  -I "$SRC" \
  "$SRC/OmnixVoiceBridge.m" \
  -o "$OBJ"

rm -f "$LIB"
xcrun -sdk iphonesimulator ar rcs "$LIB" "$OBJ"

echo "build-ios-bridge: SUCCESS"
ls -la "$OBJ" "$LIB"
