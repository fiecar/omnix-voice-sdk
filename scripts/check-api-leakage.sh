#!/usr/bin/env bash
# Fail if public Omnix headers/APIs leak Baresip/re types (Issue #1 §12).
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

# SDK-032+: public Kotlin API (com.omnix.voice/*.kt — not internal/)
KT_DIR="$ROOT/android/src/main/java/com/omnix/voice"
if [[ -d "$KT_DIR" ]]; then
  KT_PATTERNS=(
    'baresip'
    'struct[[:space:]]+ua'
    'struct[[:space:]]+call'
    'struct[[:space:]]+account'
    '[[:space:]]re_'
    'mem_alloc'
    'mem_deref'
    '[[:space:]]external[[:space:]]'
  )
  while IFS= read -r -d '' kt; do
    for pat in "${KT_PATTERNS[@]}"; do
      if grep -Eni "$pat" "$kt" | grep -Ev 'MUST NOT|must never|Baresip/re|no `external`|No `external`' >/dev/null; then
        echo "check-api-leakage: matched /$pat/ in $kt" >&2
        grep -Eni "$pat" "$kt" >&2 || true
        fail "API leakage in $kt"
      fi
    done
  done < <(find "$KT_DIR" -maxdepth 1 -type f -name '*.kt' -print0)
fi

# SDK-040+: public Objective-C bridge headers (ios/Sources/OmnixVoiceBridge/*.h)
OBJC_DIR="$ROOT/ios/Sources/OmnixVoiceBridge"
if [[ -d "$OBJC_DIR" ]]; then
  OBJC_PATTERNS=(
    'baresip\.h'
    '[[:space:]]re\.h'
    'struct[[:space:]]+ua'
    'struct[[:space:]]+call'
    'struct[[:space:]]+account'
    'struct[[:space:]]+mqueue'
    'enum[[:space:]]+ua_event'
    'mem_alloc'
    'mem_deref'
  )
  while IFS= read -r -d '' h; do
    if grep -Eiq '^\s*#\s*include\s*[<"]baresip\.h[>"]' "$h"; then
      fail "$h includes baresip.h"
    fi
    if grep -Eiq '^\s*#\s*include\s*[<"]re\.h[>"]' "$h"; then
      fail "$h includes re.h"
    fi
    for pat in "${OBJC_PATTERNS[@]}"; do
      if grep -En "$pat" "$h" | grep -Ev 'MUST NOT|must not|Baresip/re|no Baresip' >/dev/null; then
        echo "check-api-leakage: matched /$pat/ in $h" >&2
        grep -En "$pat" "$h" >&2 || true
        fail "API leakage in $h"
      fi
    done
  done < <(find "$OBJC_DIR" -maxdepth 1 -type f -name '*.h' -print0)
fi

echo "check-api-leakage: PASS"
