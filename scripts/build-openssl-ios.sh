#!/usr/bin/env bash
# Build static OpenSSL (libssl.a / libcrypto.a) for iOS device + arm64 simulator.
# [MACOS REQUIRED — needs Xcode, perl, make]
# Does NOT produce shared libraries (Configure: no-shared).
set -euo pipefail

fail() { echo "build-openssl-ios: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPENSSL_SRC="${OPENSSL_SRC:-$ROOT/third_party/openssl}"
OUT_ROOT="${OUT_ROOT:-$ROOT/build/openssl-ios}"
IOS_MIN="${IOS_MIN:-15.0}"

[[ "$(uname -s)" == "Darwin" ]] || fail "must run on macOS (got $(uname -s))"
[[ -d "$OPENSSL_SRC" ]] || fail "missing OpenSSL source at $OPENSSL_SRC"
[[ -f "$OPENSSL_SRC/Configure" ]] || fail "OpenSSL Configure missing"
command -v perl >/dev/null || fail "perl is required"
command -v make >/dev/null || fail "make is required"
command -v xcrun >/dev/null || fail "xcrun / Xcode is required"
command -v shasum >/dev/null || fail "shasum is required"

mkdir -p "$OUT_ROOT"
: > "$OUT_ROOT/SHA256SUMS"

JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

# name|openssl-target
TARGETS=(
  "iphoneos-arm64|ios64-xcrun"
  "iphonesimulator-arm64|iossimulator-arm64-xcrun"
)

echo "build-openssl-ios: source=$OPENSSL_SRC minIOS=$IOS_MIN"

for entry in "${TARGETS[@]}"; do
  name="${entry%%|*}"
  target="${entry##*|}"
  build_dir="$OUT_ROOT/build-$name"
  prefix="$OUT_ROOT/$name"
  rm -rf "$build_dir" "$prefix"
  mkdir -p "$build_dir" "$prefix"

  echo "build-openssl-ios: configuring $name ($target)"
  (
    cd "$build_dir"
    # Out-of-tree Configure. Invoke via perl (vendored sources may lack +x).
    # Do not pass page-size flags. Static only.
    perl "$OPENSSL_SRC/Configure" "$target" \
      no-shared \
      no-tests \
      -mios-version-min="${IOS_MIN}" \
      --prefix="$prefix" \
      --openssldir="$prefix/ssl"
    echo "build-openssl-ios: building $name"
    make -j"$JOBS"
    make install_sw
  )

  [[ -f "$prefix/lib/libssl.a" ]] || fail "missing libssl.a for $name"
  [[ -f "$prefix/lib/libcrypto.a" ]] || fail "missing libcrypto.a for $name"
  # Fail closed if shared slipped in
  if compgen -G "$prefix/lib/libssl*.dylib" >/dev/null || \
     compgen -G "$prefix/lib/libcrypto*.dylib" >/dev/null; then
    fail "shared OpenSSL libraries found under $prefix/lib"
  fi

  ssl_hash="$(shasum -a 256 "$prefix/lib/libssl.a" | awk '{print $1}')"
  crypto_hash="$(shasum -a 256 "$prefix/lib/libcrypto.a" | awk '{print $1}')"
  echo "$ssl_hash  $name/lib/libssl.a" >> "$OUT_ROOT/SHA256SUMS"
  echo "$crypto_hash  $name/lib/libcrypto.a" >> "$OUT_ROOT/SHA256SUMS"
  echo "build-openssl-ios: OK $name"
done

python3 - <<PY
import json, os, datetime
root = os.environ.get("OUT_ROOT", r"""$OUT_ROOT""")
meta = {
  "component": "openssl-ios-static",
  "builtAt": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
  "iosMin": r"""$IOS_MIN""",
  "slices": ["iphoneos-arm64", "iphonesimulator-arm64"],
}
with open(os.path.join(root, "ARTIFACT_META.json"), "w", encoding="utf-8") as f:
  json.dump(meta, f, indent=2)
  f.write("\n")
print("build-openssl-ios: wrote ARTIFACT_META.json")
PY

echo "build-openssl-ios: SUCCESS"
cat "$OUT_ROOT/SHA256SUMS"
