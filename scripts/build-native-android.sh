#!/usr/bin/env bash
# Cross-compile Omnix native static libs for one Android ABI (SDK-009).
# Requires ANDROID_NDK_HOME (NDK ≥ r28), cmake, ninja, and pinned OpenSSL
# under build/openssl-android/<abi> (or OMNIX_OPENSSL_ROOT).
set -euo pipefail

fail() { echo "build-native-android: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ABI="${ABI:-arm64-v8a}"
ANDROID_PLATFORM="${ANDROID_PLATFORM:-android-26}"
BUILD_DIR="${BUILD_DIR:-$ROOT/build/android-$ABI}"
OPENSSL_ROOT="${OMNIX_OPENSSL_ROOT:-$ROOT/build/openssl-android/$ABI}"

[[ -n "${ANDROID_NDK_HOME:-}" ]] || fail "ANDROID_NDK_HOME must point at a pinned NDK ≥ r28"
TOOLCHAIN="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake"
[[ -f "$TOOLCHAIN" ]] || fail "NDK toolchain missing: $TOOLCHAIN"
[[ -f "$OPENSSL_ROOT/lib/libssl.a" ]] || fail "Pinned OpenSSL missing at $OPENSSL_ROOT"
command -v cmake >/dev/null || fail "cmake is required"
command -v ninja >/dev/null || fail "ninja is required"

echo "build-native-android: ABI=$ABI NDK=$ANDROID_NDK_HOME"
echo "build-native-android: OpenSSL=$OPENSSL_ROOT"
echo "build-native-android: BuildDir=$BUILD_DIR"

cmake -S "$ROOT/cpp" -B "$BUILD_DIR" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DANDROID_ABI="$ABI" \
  -DANDROID_PLATFORM="$ANDROID_PLATFORM" \
  -DANDROID_STL=c++_static \
  -DSTATIC=ON \
  -DOMNIX_OPENSSL_ROOT="$OPENSSL_ROOT"

cmake --build "$BUILD_DIR" --target re baresip omnix_voice

re_lib="$(find "$BUILD_DIR" -name 'libre.a' -o -name 're.a' | head -n1 || true)"
baresip_lib="$(find "$BUILD_DIR" -name 'libbaresip.a' -o -name 'baresip.a' | head -n1 || true)"
[[ -n "$re_lib" ]] || fail "libre.a / re.a not found in build output"
[[ -n "$baresip_lib" ]] || fail "libbaresip.a not found in build output"

echo "PASS: $re_lib"
echo "PASS: $baresip_lib"
echo "build-native-android: OK"
