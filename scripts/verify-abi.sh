#!/usr/bin/env bash
# SDK-037 — verify all 3 Android ABIs present in a release AAR.
# Semantics match scripts/verify-abi.ps1.
set -euo pipefail

if [[ $# -lt 1 || -z "${1:-}" ]]; then
  echo "Usage: $0 <OmnixVoiceSDK-x.y.z.aar>" >&2
  exit 2
fi

AAR=$1
if [[ ! -f "$AAR" ]]; then
  echo "ERROR: AAR not found: $AAR" >&2
  exit 1
fi

for ABI in arm64-v8a armeabi-v7a x86_64; do
  unzip -l "$AAR" | grep -q "jni/$ABI/libomnixvoice.so" || { echo "ERROR: Missing $ABI"; exit 1; }
  echo "OK: $ABI"
done
