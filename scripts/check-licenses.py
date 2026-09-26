# SDK-059: fail if a vendored component is missing attribution, or if a
# file that can be compiled into a shipped artifact is copyleft-only.
# Dual-licensed files (GPL or BSD/Apache/MIT/MPL) are reported, not failed.
# Paths in scripts/license-allowlist.txt are not shipped (build tooling).
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "third_party" / "SOURCE_MANIFEST.json"
NOTICES = ROOT / "THIRD_PARTY_NOTICES.md"
ALLOW = ROOT / "scripts" / "license-allowlist.txt"

COPYLEFT = (
    "GNU General Public License",
    "GNU Lesser General Public",
    "GNU Affero General Public",
    "SPDX-License-Identifier: GPL",
    "SPDX-License-Identifier: LGPL",
    "SPDX-License-Identifier: AGPL",
)
PERMISSIVE = (
    "BSD License",
    "BSD-3-Clause",
    "Apache License",
    "MIT License",
    "Mozilla Public License",
)
SKIP_SUFFIX = {
    ".a", ".o", ".so", ".dylib", ".png", ".jpg", ".jpeg", ".gif",
    ".webp", ".ico", ".pdf", ".zip", ".gz", ".tgz", ".jar", ".aar",
    ".xcframework", ".bin", ".dat", ".exe", ".dll",
}


def allow_prefixes():
    prefixes = []
    if not ALLOW.is_file():
        return prefixes
    for raw in ALLOW.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip().replace("\\", "/")
        if line:
            prefixes.append(line)
    return prefixes


def allowed(rel, prefixes):
    rel = rel.replace("\\", "/")
    for prefix in prefixes:
        if rel == prefix or rel.startswith(prefix):
            return True
    return False


def main():
    failed = False
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    notices = NOTICES.read_text(encoding="utf-8")
    prefixes = allow_prefixes()

    for comp in manifest["components"]:
        name = comp["component"]
        license_copy = ROOT / "LICENSES" / f"{name}-LICENSE.txt"
        if not license_copy.is_file() or license_copy.stat().st_size == 0:
            print(f"FAIL: missing LICENSES/{name}-LICENSE.txt")
            failed = True
        if name not in notices:
            print(f"FAIL: THIRD_PARTY_NOTICES.md missing {name}")
            failed = True
        declared = comp.get("license", "")
        if any(tag in declared.upper() for tag in ("GPL", "LGPL", "AGPL")):
            print(f"FAIL: manifest license for {name} is {declared}")
            failed = True

    for path in (ROOT / "third_party").rglob("*"):
        if not path.is_file():
            continue
        if path.suffix.lower() in SKIP_SUFFIX:
            continue
        rel = path.relative_to(ROOT).as_posix()
        if allowed(rel, prefixes):
            continue
        if path.stat().st_size > 1_000_000:
            continue
        data = path.read_bytes()
        if b"\0" in data[:1024]:
            continue
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            text = data.decode("latin-1", errors="replace")
        if not any(tok in text for tok in COPYLEFT):
            continue
        if any(tok in text for tok in PERMISSIVE):
            print(f"NOTE: dual-licensed, permissive alternative present: {rel}")
            continue
        print(f"FAIL: copyleft-only file not on the non-shipped allowlist: {rel}")
        failed = True

    if failed:
        print("ERROR: license check FAILED")
        return 1
    print("SUCCESS: license check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
