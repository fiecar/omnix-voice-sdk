#!/usr/bin/env bash
# Skeleton wrapper around import-upstream for documented upstream updates.
# Semantics match scripts/update-upstream.ps1.
# Does NOT choose versions — edit SOURCE_MANIFEST.json first (Issue #1 §13).
set -euo pipefail

usage() {
  echo "Usage: $0 <component>" >&2
  exit 2
}

fail() {
  echo "update-upstream: $*" >&2
  exit 1
}

[[ $# -eq 1 ]] || usage
COMPONENT="$1"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMPORT="$ROOT/scripts/import-upstream.sh"
[[ -f "$IMPORT" ]] || fail "missing $IMPORT"
[[ -x "$IMPORT" ]] || chmod +x "$IMPORT"

echo "update-upstream: delegating to import-upstream for component=$COMPONENT"
echo "update-upstream: ensure SOURCE_MANIFEST.json was edited first (Issue #1 section 13)"
exec "$IMPORT" "$COMPONENT"
