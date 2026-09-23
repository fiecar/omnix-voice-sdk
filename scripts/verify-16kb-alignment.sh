#!/usr/bin/env bash
# SDK-038 — Linux CI canonical 16 KB page-size check for every .so in an AAR.
# Semantics match scripts/verify-16kb-alignment.ps1.
# Tool: llvm-readelf from the pinned NDK (not system readelf).
set -euo pipefail

if [[ $# -lt 1 || -z "${1:-}" ]]; then
  echo "Usage: $0 <OmnixVoiceSDK-x.y.z.aar>" >&2
  exit 2
fi

AAR=$1
if [[ ! -f "$AAR" ]]; then
  echo "FAIL: AAR not found: $AAR" >&2
  exit 1
fi

if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
  echo "FAIL: ANDROID_NDK_HOME is not set (need pinned NDK llvm-readelf)" >&2
  exit 1
fi

# Resolve host prebuilt dir (linux-x86_64 / darwin-x86_64 / darwin-arm64).
READELF=${READELF:-}
if [[ -z "$READELF" ]]; then
  for host in linux-x86_64 darwin-x86_64 darwin-arm64; do
    cand="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$host/bin/llvm-readelf"
    if [[ -x "$cand" ]]; then
      READELF=$cand
      break
    fi
  done
fi
if [[ -z "${READELF}" || ! -x "$READELF" ]]; then
  echo "FAIL: llvm-readelf not found under \$ANDROID_NDK_HOME/toolchains/llvm/prebuilt" >&2
  exit 1
fi

ALLOW=${ALLOW:-android/shipped-native-libs.txt}
if [[ ! -f "$ALLOW" ]]; then
  echo "FAIL: allowlist not found: $ALLOW" >&2
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
unzip -q "$AAR" -d "$TMP"

mapfile -t SOS < <(cd "$TMP" && find . -type f -name '*.so' | sed 's|^\./||' | sort)
(( ${#SOS[@]} > 0 )) || { echo "FAIL: no .so in $AAR"; exit 1; }

FAILED=0
for ABI in arm64-v8a armeabi-v7a x86_64; do
  while read -r LIB; do
    [[ -z "$LIB" ]] && continue
    [[ -f "$TMP/jni/$ABI/$LIB" ]] || { echo "FAIL: missing jni/$ABI/$LIB"; FAILED=1; }
  done < "$ALLOW"
done

for REL in "${SOS[@]}"; do
  NAME=$(basename "$REL")
  ABI=$(basename "$(dirname "$REL")")
  if [[ "$REL" != "jni/$ABI/$NAME" ]] || ! grep -qxF "$NAME" "$ALLOW"; then
    echo "FAIL: unexpected native library $REL"
    FAILED=1
    continue
  fi

  HDRS=$("$READELF" -lW "$TMP/$REL")
  BAD=0
  N=0
  while read -r A; do
    [[ -z "$A" ]] && continue
    N=$((N + 1))
    V=$((A))
    if (( V < 16384 || (V & (V - 1)) != 0 )); then
      BAD=1
    fi
  done < <(awk '$1=="LOAD"{print $NF}' <<<"$HDRS")
  (( N > 0 )) || BAD=1

  RV=""
  RM=""
  read -r RV RM < <(awk '$1=="GNU_RELRO"{print $3, $6}' <<<"$HDRS") || true
  if [[ -n "${RV:-}" && -n "${RM:-}" ]]; then
    if (( (RV + RM) % 16384 != 0 )); then
      echo "RELRO-CHECK: $REL end not 16 KB aligned"
      BAD=1
    fi
  fi

  if (( BAD )); then
    if [[ "$ABI" == armeabi-v7a ]]; then
      echo "WARN (32-bit, informational): $REL"
    else
      echo "FAIL: $REL"
      FAILED=1
    fi
  else
    echo "OK: $REL"
  fi
  unset RV RM
done

(( FAILED == 0 )) || {
  echo "ERROR: 16 KB check FAILED (see https://developer.android.com/guide/practices/page-sizes)"
  exit 1
}
echo "SUCCESS: all shipped 64-bit .so are 16 KB compatible"
