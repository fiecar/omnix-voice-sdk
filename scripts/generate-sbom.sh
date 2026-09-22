#!/usr/bin/env bash
# Generate SBOM.json (SPDX 2.3) using pinned syft, then enrich from SOURCE_MANIFEST.json.
# [BASH/WSL/GIT-BASH REQUIRED] for Linux/macOS CI — semantics match generate-sbom.ps1.
set -euo pipefail

SYFT_VERSION="1.52.0"
SYFT_LICENSE="Apache-2.0"

fail() { echo "generate-sbom: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MANIFEST="$ROOT/third_party/SOURCE_MANIFEST.json"
OUT="$ROOT/SBOM.json"
ENRICH="$ROOT/scripts/enrich-sbom.js"

[[ -f "$MANIFEST" ]] || fail "Missing third_party/SOURCE_MANIFEST.json"
[[ -d "$ROOT/LICENSES" ]] || fail "Missing LICENSES/"
[[ -f "$ENRICH" ]] || fail "Missing scripts/enrich-sbom.js"
command -v node >/dev/null || fail "node is required"
command -v curl >/dev/null || fail "curl is required"
command -v tar >/dev/null || fail "tar is required"

uname_s="$(uname -s | tr '[:upper:]' '[:lower:]')"
uname_m="$(uname -m)"
case "$uname_s-$uname_m" in
  linux-x86_64|linux-amd64) syft_asset="syft_${SYFT_VERSION}_linux_amd64.tar.gz" ;;
  linux-aarch64|linux-arm64) syft_asset="syft_${SYFT_VERSION}_linux_arm64.tar.gz" ;;
  darwin-x86_64) syft_asset="syft_${SYFT_VERSION}_darwin_amd64.tar.gz" ;;
  darwin-arm64) syft_asset="syft_${SYFT_VERSION}_darwin_arm64.tar.gz" ;;
  *) fail "Unsupported platform: $uname_s/$uname_m" ;;
esac

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/omnix-voice-sdk/tools/syft/v${SYFT_VERSION}"
mkdir -p "$CACHE"
SYFT_BIN="$CACHE/syft"
if [[ ! -x "$SYFT_BIN" ]]; then
  url="https://github.com/anchore/syft/releases/download/v${SYFT_VERSION}/${syft_asset}"
  echo "generate-sbom: downloading pinned syft v${SYFT_VERSION}"
  echo "generate-sbom: $url"
  tmp="$(mktemp -d)"
  curl -fsSL "$url" -o "$tmp/syft.tgz"
  tar -xzf "$tmp/syft.tgz" -C "$CACHE"
  rm -rf "$tmp"
  [[ -x "$SYFT_BIN" ]] || fail "syft binary missing after extract"
fi

echo "generate-sbom: tool=syft version=${SYFT_VERSION} license=${SYFT_LICENSE}"
"$SYFT_BIN" version

RAW="$(mktemp "${TMPDIR:-/tmp}/omnix-sbom-raw.XXXXXX.json")"
cleanup() { rm -f "$RAW"; }
trap cleanup EXIT

echo "generate-sbom: scanning repository (excluding third_party and .git)"
"$SYFT_BIN" dir:. \
  --exclude './third_party/**' \
  --exclude './.git/**' \
  --source-name 'omnix-voice-sdk' \
  -o "spdx-json=$RAW"

echo "generate-sbom: enriching from SOURCE_MANIFEST.json"
node "$ENRICH" --input "$RAW" --output "$OUT" --manifest "$MANIFEST" --repo-root "$ROOT"
echo "generate-sbom: wrote $OUT"
