#!/usr/bin/env bash
# Build static OpenSSL (libssl.a / libcrypto.a) for Android ABIs.
# [BASH/WSL REQUIRED — needs perl + make + Android NDK ≥ r28]
# Does NOT produce shared libraries (Configure: no-shared).
set -euo pipefail

fail() { echo "build-openssl-android: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPENSSL_SRC="${OPENSSL_SRC:-$ROOT/third_party/openssl}"
OUT_ROOT="${OUT_ROOT:-$ROOT/build/openssl-android}"
ANDROID_API="${ANDROID_API:-26}"
ABIS="${ABIS:-arm64-v8a armeabi-v7a x86_64}"

[[ -d "$OPENSSL_SRC" ]] || fail "missing OpenSSL source at $OPENSSL_SRC"
[[ -x "$OPENSSL_SRC/Configure" || -f "$OPENSSL_SRC/Configure" ]] || fail "OpenSSL Configure missing"
command -v perl >/dev/null || fail "perl is required"
command -v make >/dev/null || fail "make is required"
command -v sha256sum >/dev/null || fail "sha256sum is required"

if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
  fail "ANDROID_NDK_HOME must point at a pinned NDK ≥ r28"
fi
[[ -d "$ANDROID_NDK_HOME" ]] || fail "ANDROID_NDK_HOME is not a directory: $ANDROID_NDK_HOME"
export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"

HOST_TAG="linux-x86_64"
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64|Linux-amd64) HOST_TAG="linux-x86_64" ;;
  Darwin-arm64) HOST_TAG="darwin-arm64" ;;
  Darwin-x86_64) HOST_TAG="darwin-x86_64" ;;
  *) fail "Unsupported host for this script: $(uname -s)/$(uname -m) (use Linux CI or WSL)" ;;
esac

TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$HOST_TAG"
if [[ ! -d "$TOOLCHAIN" && "$HOST_TAG" == "darwin-arm64" ]]; then
  # Some NDK packages only ship darwin-x86_64 (Rosetta)
  TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64"
  HOST_TAG="darwin-x86_64"
fi
[[ -d "$TOOLCHAIN" ]] || fail "NDK toolchain missing: $TOOLCHAIN"
export PATH="$TOOLCHAIN/bin:$PATH"

map_abi_to_target() {
  case "$1" in
    arm64-v8a) echo "android-arm64" ;;
    armeabi-v7a) echo "android-arm" ;;
    x86_64) echo "android-x86_64" ;;
    *) fail "Unsupported ABI: $1" ;;
  esac
}

mkdir -p "$OUT_ROOT"
: > "$OUT_ROOT/SHA256SUMS"

echo "build-openssl-android: NDK=$ANDROID_NDK_HOME API=$ANDROID_API"
echo "build-openssl-android: source=$OPENSSL_SRC"

JOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"

for abi in $ABIS; do
  target="$(map_abi_to_target "$abi")"
  build_dir="$OUT_ROOT/build-$abi"
  prefix="$OUT_ROOT/$abi"
  rm -rf "$build_dir" "$prefix"
  mkdir -p "$build_dir" "$prefix"

  echo "build-openssl-android: configuring $abi ($target)"
  (
    cd "$build_dir"
    # Out-of-tree Configure (OpenSSL 3.x)
    "$OPENSSL_SRC/Configure" "$target" \
      no-shared \
      no-tests \
      -D__ANDROID_API__="${ANDROID_API}" \
      --prefix="$prefix" \
      --openssldir="$prefix/ssl"
    echo "build-openssl-android: building $abi"
    make -j"$JOBS"
    echo "build-openssl-android: installing $abi"
    make install_sw
  )

  libssl="$prefix/lib/libssl.a"
  libcrypto="$prefix/lib/libcrypto.a"
  [[ -f "$libssl" ]] || fail "missing $libssl"
  [[ -f "$libcrypto" ]] || fail "missing $libcrypto"
  if compgen -G "$prefix/lib/libssl.so*" >/dev/null 2>&1 || compgen -G "$prefix/lib/libcrypto.so*" >/dev/null 2>&1; then
    fail "shared OpenSSL libraries were produced under $prefix/lib (forbidden)"
  fi

  (
    cd "$OUT_ROOT"
    sha256sum "$abi/lib/libssl.a" "$abi/lib/libcrypto.a" >> SHA256SUMS
  )
  echo "build-openssl-android: OK $abi"
done

OPENSSL_COMMIT="$(python3 -c "import json; m=json.load(open(r'$ROOT/third_party/SOURCE_MANIFEST.json')); print(next(c['commit'] for c in m['components'] if c['component']=='openssl'))")"

ABIS_JSON="$(printf '%s\n' $ABIS | python3 -c 'import sys,json; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))')"
cat > "$OUT_ROOT/ARTIFACT_META.json" <<EOF
{
  "component": "openssl-android-static",
  "opensslCommit": "$OPENSSL_COMMIT",
  "androidApi": $ANDROID_API,
  "abis": $ABIS_JSON,
  "sharedLibraries": false
}
EOF

echo "build-openssl-android: wrote $OUT_ROOT/SHA256SUMS and ARTIFACT_META.json"
echo "build-openssl-android: SUCCESS"
