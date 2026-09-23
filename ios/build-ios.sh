#!/usr/bin/env bash
# SDK-039 — build Omnix native static libs for iOS device + arm64 simulator.
# [MACOS REQUIRED]
set -euo pipefail

fail() { echo "build-ios: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLCHAIN="$ROOT/third_party/ios-cmake/ios.toolchain.cmake"
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-15.0}"
OPENSSL_ROOT_BASE="${OPENSSL_ROOT_BASE:-$ROOT/build/openssl-ios}"

[[ "$(uname -s)" == "Darwin" ]] || fail "must run on macOS"
[[ -f "$TOOLCHAIN" ]] || fail "missing ios-cmake toolchain at $TOOLCHAIN (run import-upstream ios-cmake)"
[[ -f "$ROOT/cpp/CMakeLists.txt" ]] || fail "missing cpp/CMakeLists.txt"

if [[ ! -f "$OPENSSL_ROOT_BASE/iphoneos-arm64/lib/libssl.a" ]]; then
  echo "build-ios: building OpenSSL iOS static slices first"
  chmod +x "$ROOT/scripts/build-openssl-ios.sh"
  "$ROOT/scripts/build-openssl-ios.sh"
fi

build_one() {
  local platform="$1"
  local out_dir="$2"
  local openssl_slice="$3"

  local openssl_root="$OPENSSL_ROOT_BASE/$openssl_slice"
  [[ -f "$openssl_root/lib/libssl.a" ]] || fail "missing OpenSSL at $openssl_root (run scripts/build-openssl-ios.sh)"
  [[ -f "$openssl_root/lib/libcrypto.a" ]] || fail "missing libcrypto.a at $openssl_root"

  echo "build-ios: PLATFORM=$platform -> $out_dir (OpenSSL=$openssl_slice)"
  rm -rf "$out_dir"
  cmake -S "$ROOT/cpp" -B "$out_dir" \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
    -DPLATFORM="$platform" \
    -DDEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
    -DENABLE_BITCODE=OFF \
    -DCMAKE_MACOSX_BUNDLE=OFF \
    -DSTATIC=ON \
    -DOMNIX_OPENSSL_ROOT="$openssl_root" \
    -DOMNIX_BUILD_TESTS=OFF
  cmake --build "$out_dir" --parallel "$(sysctl -n hw.ncpu 2>/dev/null || echo 4)" \
    --target baresip re omnix_voice

  # Locate static archives (baresip/re CMake output layout) and stage next to build root
  # for the SDK-039 acceptance paths.
  local baresip
  baresip="$(find "$out_dir" -name 'libbaresip.a' -type f | head -n 1 || true)"
  local re
  re="$(find "$out_dir" -name 'libre.a' -type f | head -n 1 || true)"
  local omnix
  omnix="$(find "$out_dir" -name 'libomnix_voice.a' -type f | head -n 1 || true)"
  [[ -n "$baresip" ]] || fail "libbaresip.a not produced under $out_dir"
  [[ -n "$re" ]] || fail "libre.a not produced under $out_dir"
  [[ -n "$omnix" ]] || fail "libomnix_voice.a not produced under $out_dir"
  stage_one() {
    local src="$1" dest="$2"
    if [[ "$(cd "$(dirname "$src")" && pwd)/$(basename "$src")" == \
          "$(cd "$(dirname "$dest")" && pwd)/$(basename "$dest")" ]]; then
      return 0
    fi
    cp -f "$src" "$dest"
  }
  stage_one "$baresip" "$out_dir/libbaresip.a"
  stage_one "$re" "$out_dir/libre.a"
  stage_one "$omnix" "$out_dir/libomnix_voice.a"
  echo "build-ios: staged $out_dir/libbaresip.a"
}

build_one "OS64" "$ROOT/build/ios-device" "iphoneos-arm64"
build_one "SIMULATORARM64" "$ROOT/build/ios-sim" "iphonesimulator-arm64"

# Sanity: audiounit must be linked into the iOS module set (grep symbols or module map).
# Prefer nm on the staged archive for a lightweight check.
if command -v nm >/dev/null; then
  if ! nm "$ROOT/build/ios-device/libbaresip.a" 2>/dev/null | grep -q 'audiounit\|au_alloc\|augen'; then
    echo "build-ios: WARN — could not confirm audiounit symbols via nm (non-fatal; CI logs MODULES)"
  fi
fi

echo "build-ios: SUCCESS"
ls -la "$ROOT/build/ios-device/libbaresip.a" "$ROOT/build/ios-sim/libbaresip.a"
