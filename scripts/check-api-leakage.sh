#!/usr/bin/env bash
# Fail if public Omnix headers leak Baresip/re types (Issue #1 §12).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { echo "check-api-leakage: $*" >&2; exit 1; }

HEADERS=(
  "$ROOT/cpp/include/omnix_voice/omnix_voice.h"
  "$ROOT/cpp/include/omnix_voice/omnix_types.h"
)

for h in "${HEADERS[@]}"; do
  [[ -f "$h" ]] || fail "missing public header: $h"
done

# Includes
for h in "${HEADERS[@]}"; do
  if grep -Eiq '^\s*#\s*include\s*[<"]baresip\.h[>"]' "$h"; then
    fail "$h includes baresip.h"
  fi
  if grep -Eiq '^\s*#\s*include\s*[<"]re\.h[>"]' "$h"; then
    fail "$h includes re.h"
  fi
done

PATTERNS=(
  'struct[[:space:]]+ua[[:space:]]*\*'
  'struct[[:space:]]+call[[:space:]]*\*'
  'struct[[:space:]]+account[[:space:]]*\*'
  'struct[[:space:]]+mqueue[[:space:]]*\*'
  'enum[[:space:]]+ua_event'
  'enum[[:space:]]+call_event'
  'enum[[:space:]]+vidmode'
  'enum[[:space:]]+sdp_dir'
)

for h in "${HEADERS[@]}"; do
  for pat in "${PATTERNS[@]}"; do
    if grep -En "$pat" "$h" | grep -Ev 'MUST NOT|do NOT|Baresip / re types MUST NOT' >/dev/null; then
      echo "check-api-leakage: matched /$pat/ in $h" >&2
      grep -En "$pat" "$h" >&2 || true
      fail "API leakage in $h"
    fi
  done
done

echo "check-api-leakage: PASS"
