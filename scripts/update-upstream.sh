#!/usr/bin/env bash
# Lead-approved upstream update: import-upstream, then verify-third-party.
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
echo "update-upstream: ensure SOURCE_MANIFEST.json was edited and lead-approved first (Issue #1 section 0.3 / 13)"
"$IMPORT" "$COMPONENT"
VERIFY="$ROOT/scripts/verify-third-party.sh"
[[ -f "$VERIFY" ]] || fail "missing $VERIFY"
[[ -x "$VERIFY" ]] || chmod +x "$VERIFY"
"$VERIFY"
