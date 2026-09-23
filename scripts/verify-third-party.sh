#!/usr/bin/env bash
# Verify vendored third_party trees against TREE_SHA256SUMS (fail closed).
# Semantics match scripts/verify-third-party.ps1.
set -euo pipefail

fail() {
  echo "verify-third-party: $*" >&2
  exit 1
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUMS="$ROOT/third_party/TREE_SHA256SUMS"
MANIFEST="$ROOT/third_party/SOURCE_MANIFEST.json"

[[ -f "$SUMS" ]] || fail "Missing $SUMS — run import-upstream first"
[[ -f "$MANIFEST" ]] || fail "Missing $MANIFEST"
command -v python3 >/dev/null || fail "python3 is required"

python3 - "$ROOT" "$SUMS" "$MANIFEST" <<'PY'
import hashlib, json, os, re, sys

SKIP_RE = re.compile(r"\.(pem|key|p12|pfx|jks|keystore|dylib|so|dll|exe|a)$", re.I)
root, sums_path, manifest_path = sys.argv[1:4]

expected = {}
with open(sums_path, encoding="utf-8") as f:
    for lineno, raw in enumerate(f, 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(None, 1)
        if len(parts) != 2 or len(parts[0]) != 64:
            raise SystemExit(f"Malformed TREE_SHA256SUMS line {lineno}: {raw.rstrip()}")
        rel = parts[1].lstrip("*").replace("\\", "/")
        if SKIP_RE.search(rel):
            continue
        if rel in expected:
            raise SystemExit(f"Duplicate path in TREE_SHA256SUMS: {rel}")
        expected[rel] = parts[0].lower()

if not expected:
    raise SystemExit("TREE_SHA256SUMS is empty")

manifest = json.load(open(manifest_path, encoding="utf-8"))
actual = {}
for c in manifest["components"]:
    vendored = os.path.join(root, c["vendoredPath"])
    if not os.path.isdir(vendored):
        continue
    for dirpath, _, filenames in os.walk(vendored):
        for name in filenames:
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, root).replace("\\", "/")
            if SKIP_RE.search(rel):
                continue
            h = hashlib.sha256()
            with open(path, "rb") as fh:
                for chunk in iter(lambda: fh.read(1024 * 1024), b""):
                    h.update(chunk)
            actual[rel] = h.hexdigest()

errors = []
for rel, exp in sorted(expected.items()):
    if rel not in actual:
        errors.append(f"MISSING: {rel}")
    elif actual[rel] != exp:
        errors.append(f"MODIFIED: {rel} (expected {exp}, got {actual[rel]})")
for rel in sorted(actual):
    if rel not in expected:
        errors.append(f"UNEXPECTED: {rel}")

if errors:
    print(f"verify-third-party: FAILED ({len(errors)} issue(s))")
    for e in errors:
        print(f"  {e}")
    print("If a change is intentional, record it in PATCHES.md and regenerate TREE_SHA256SUMS via import-upstream (lead-approved).")
    sys.exit(1)

print(f"verify-third-party: OK ({len(actual)} files)")
PY
