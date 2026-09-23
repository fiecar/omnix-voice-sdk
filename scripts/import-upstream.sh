#!/usr/bin/env bash
# Fail-closed, commit-anchored import of a vendored upstream component.
# Linux/macOS CI — [BASH/WSL/GIT-BASH REQUIRED]
# Semantics match scripts/import-upstream.ps1.
set -euo pipefail

usage() {
  echo "Usage: $0 <component>" >&2
  exit 2
}

fail() {
  echo "import-upstream: $*" >&2
  exit 1
}

[[ $# -eq 1 ]] || usage
COMPONENT="$1"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT/third_party/SOURCE_MANIFEST.json"
[[ -f "$MANIFEST" ]] || fail "SOURCE_MANIFEST.json not found at $MANIFEST"

command -v git >/dev/null || fail "git is required"
command -v tar >/dev/null || fail "tar is required"
command -v sha256sum >/dev/null || command -v shasum >/dev/null || fail "sha256sum or shasum is required"
command -v python3 >/dev/null || fail "python3 is required for JSON updates"

sha256_file() {
  if command -v sha256sum >/dev/null; then
    sha256sum "$1" | awk '{print tolower($1)}'
  else
    shasum -a 256 "$1" | awk '{print tolower($1)}'
  fi
}

forbidden_url() {
  local u
  u="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  [[ "$u" == *"/tarball/"* ]] && return 0
  [[ "$u" == *"/archive/refs/heads/"* ]] && return 0
  [[ "$u" == *"/archive/main."* || "$u" == *"/archive/master."* ]] && return 0
  return 1
}

read_field() {
  local comp="$1" field="$2"
  python3 - "$MANIFEST" "$comp" "$field" <<'PY'
import json, sys
manifest = json.load(open(sys.argv[1], encoding="utf-8"))
comp, field = sys.argv[2], sys.argv[3]
for c in manifest["components"]:
    if c["component"] == comp:
        print(c.get(field, "") or "")
        sys.exit(0)
sys.exit("component not found")
PY
}

update_manifest_fields() {
  local comp="$1" sha="$2" date="$3"
  python3 - "$MANIFEST" "$comp" "$sha" "$date" <<'PY'
import json, sys
path, comp, sha, date = sys.argv[1:5]
with open(path, encoding="utf-8") as f:
    manifest = json.load(f)
found = False
for c in manifest["components"]:
    if c["component"] == comp:
        c["archiveSha256"] = sha
        c["importDate"] = date
        found = True
        break
if not found:
    raise SystemExit("component not found")
with open(path, "w", encoding="utf-8", newline="\n") as f:
    json.dump(manifest, f, indent=2)
    f.write("\n")
PY
}

write_sha256sums() {
  python3 - "$MANIFEST" "$ROOT/third_party/SHA256SUMS" <<'PY'
import json, sys
manifest = json.load(open(sys.argv[1], encoding="utf-8"))
out = sys.argv[2]
lines = []
for c in manifest["components"]:
    sha = (c.get("archiveSha256") or "").strip().lower()
    if not sha:
        continue
    name = f'{c["component"]}-{c["commit"]}.tar.gz'
    lines.append(f"{sha}  {name}")
with open(out, "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(lines) + ("\n" if lines else ""))
PY
}

write_tree_sha256sums() {
  python3 - "$MANIFEST" "$ROOT" "$ROOT/third_party/TREE_SHA256SUMS" <<'PY'
import hashlib, json, os, sys
manifest = json.load(open(sys.argv[1], encoding="utf-8"))
root = sys.argv[2]
out = sys.argv[3]
lines = []
for c in manifest["components"]:
    vendored = os.path.join(root, c["vendoredPath"])
    if not os.path.isdir(vendored):
        continue
    for dirpath, _, filenames in os.walk(vendored):
        for name in sorted(filenames):
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, root).replace("\\", "/")
            h = hashlib.sha256()
            with open(path, "rb") as f:
                for chunk in iter(lambda: f.read(1024 * 1024), b""):
                    h.update(chunk)
            lines.append(f"{h.hexdigest()}  {rel}")
lines.sort(key=lambda s: s.split("  ", 1)[1])
with open(out, "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(lines) + ("\n" if lines else ""))
PY
}

update_upstream_md() {
  local comp="$1" version="$2" commit="$3" date="$4" license="$5" sha="$6"
  local path="$ROOT/UPSTREAM.md"
  local marker="<!-- IMPORT:${comp} -->"
  local line="${comp}: tag=${version}, commit=${commit}, imported=${date}, license=${license}, archive-sha256=${sha}"
  local block="${marker}"$'\n'"${line}"
  if [[ -f "$path" ]]; then
    python3 - "$path" "$marker" "$block" <<'PY'
import re, sys
path, marker, block = sys.argv[1:4]
text = open(path, encoding="utf-8").read()
if marker in text:
    text = re.sub(
        re.escape(marker) + r"\n.*?(?=\n<!-- IMPORT:|\n## |\Z)",
        block.rstrip() + "\n",
        text,
        count=1,
        flags=re.S,
    )
else:
    if not text.endswith("\n"):
        text += "\n"
    text += "\n## Imported components\n\n" + block + "\n"
open(path, "w", encoding="utf-8", newline="\n").write(text.replace("\r\n", "\n"))
PY
  fi
}

COMMIT="$(read_field "$COMPONENT" commit | tr '[:upper:]' '[:lower:]')"
VERSION="$(read_field "$COMPONENT" version)"
REPOSITORY="$(read_field "$COMPONENT" repository)"
DOWNLOAD_URL="$(read_field "$COMPONENT" downloadUrl)"
VENDORED_REL="$(read_field "$COMPONENT" vendoredPath)"
LICENSE_NAME="$(read_field "$COMPONENT" license)"
RECORDED_SHA="$(read_field "$COMPONENT" archiveSha256 | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
VENDORED_PATH="$ROOT/$VENDORED_REL"
EXPECTED_URL="${REPOSITORY%/}/archive/${COMMIT}.tar.gz"

[[ "$COMMIT" =~ ^[0-9a-f]{40}$ ]] || fail "Manifest commit must be a full 40-char SHA"
forbidden_url "$DOWNLOAD_URL" && fail "Forbidden download URL (branch/tarball/floating ref): $DOWNLOAD_URL"
[[ "$DOWNLOAD_URL" == "$EXPECTED_URL" ]] || fail "downloadUrl must be exact commit archive URL. Expected: $EXPECTED_URL Actual: $DOWNLOAD_URL"
[[ "$DOWNLOAD_URL" == *"$COMMIT"* ]] || fail "downloadUrl does not contain manifest commit SHA"

echo "import-upstream: component=$COMPONENT commit=$COMMIT"

# Tag → commit (peeled annotated, else lightweight)
TAG_COMMIT="$(git ls-remote "$REPOSITORY" "refs/tags/${VERSION}^{}" | awk 'NF{print tolower($1); exit}')"
if [[ -z "$TAG_COMMIT" ]]; then
  TAG_COMMIT="$(git ls-remote "$REPOSITORY" "refs/tags/${VERSION}" | awk 'NF{print tolower($1); exit}')"
fi
[[ -n "$TAG_COMMIT" ]] || fail "Tag refs/tags/$VERSION not found on $REPOSITORY"
[[ "$TAG_COMMIT" == "$COMMIT" ]] || fail "Tag $VERSION resolves to $TAG_COMMIT but manifest commit is $COMMIT"
echo "import-upstream: tag $VERSION -> $TAG_COMMIT (ok)"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/omnix-import.XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

ARCHIVE_NAME="${COMPONENT}-${COMMIT}.tar.gz"
GZ="$WORK/$ARCHIVE_NAME"
TAR="$WORK/${COMPONENT}-${COMMIT}.tar"
EXTRACT="$WORK/extract"
STAGE="$WORK/stage"
mkdir -p "$EXTRACT"

echo "import-upstream: downloading $DOWNLOAD_URL"
if command -v curl >/dev/null; then
  curl -fsSL "$DOWNLOAD_URL" -o "$GZ" || fail "Download failed"
elif command -v wget >/dev/null; then
  wget -q -O "$GZ" "$DOWNLOAD_URL" || fail "Download failed"
else
  fail "curl or wget is required"
fi
[[ -s "$GZ" ]] || fail "Download produced empty file"

COMPUTED="$(sha256_file "$GZ")"
echo "import-upstream: archive SHA-256 = $COMPUTED"

if [[ -z "$RECORDED_SHA" ]]; then
  echo "import-upstream: first import — recording archiveSha256"
elif [[ "$RECORDED_SHA" != "$COMPUTED" ]]; then
  fail "archiveSha256 mismatch for $COMPONENT. Recorded: $RECORDED_SHA Computed: $COMPUTED"
else
  echo "import-upstream: archiveSha256 matches recorded value"
fi

# Decompress for git get-tar-commit-id
if command -v gzip >/dev/null; then
  gzip -dc "$GZ" > "$TAR"
else
  python3 - "$GZ" "$TAR" <<'PY'
import gzip, sys
open(sys.argv[2], "wb").write(gzip.open(sys.argv[1], "rb").read())
PY
fi

TAR_COMMIT="$(git get-tar-commit-id < "$TAR" | awk '{print tolower($1); exit}')"
[[ -n "$TAR_COMMIT" ]] || fail "git get-tar-commit-id produced empty output"
[[ "$TAR_COMMIT" == "$COMMIT" ]] || fail "Archive commit-id $TAR_COMMIT does not match manifest commit $COMMIT"
echo "import-upstream: git get-tar-commit-id -> $TAR_COMMIT (ok)"

tar -xzf "$GZ" -C "$EXTRACT"
mapfile -t TOP < <(find "$EXTRACT" -mindepth 1 -maxdepth 1 -type d)
[[ "${#TOP[@]}" -eq 1 ]] || fail "Unexpected archive layout: expected one top-level directory, found ${#TOP[@]}"
SOURCE_TREE="${TOP[0]}"

LICENSE_SRC=""
for cand in LICENSE LICENSE.txt LICENSE.md COPYING; do
  if [[ -f "$SOURCE_TREE/$cand" ]]; then
    LICENSE_SRC="$SOURCE_TREE/$cand"
    break
  fi
done
[[ -n "$LICENSE_SRC" ]] || fail "LICENSE/LICENSE.txt/LICENSE.md/COPYING missing in extracted tree"

rm -rf "$STAGE"
mkdir -p "$STAGE"
tar -cf - -C "$SOURCE_TREE" . | tar -xf - -C "$STAGE"
if [[ ! -f "$STAGE/LICENSE" && ! -f "$STAGE/LICENSE.txt" && ! -f "$STAGE/LICENSE.md" && ! -f "$STAGE/COPYING" ]]; then
  fail "LICENSE missing after staging"
fi

BACKUP=""
mkdir -p "$(dirname "$VENDORED_PATH")"
if [[ -e "$VENDORED_PATH" ]]; then
  BACKUP="${VENDORED_PATH}.__bak_$$"
  rm -rf "$BACKUP"
  mv "$VENDORED_PATH" "$BACKUP"
fi

if ! mv "$STAGE" "$VENDORED_PATH"; then
  if [[ -n "$BACKUP" && -e "$BACKUP" ]]; then
    rm -rf "$VENDORED_PATH"
    mv "$BACKUP" "$VENDORED_PATH"
  fi
  fail "Failed to replace vendored tree"
fi
[[ -n "$BACKUP" && -e "$BACKUP" ]] && rm -rf "$BACKUP"

IMPORT_DATE="$(date -u +%Y-%m-%d)"
update_manifest_fields "$COMPONENT" "$COMPUTED" "$IMPORT_DATE"

mkdir -p "$ROOT/LICENSES"
LICENSE_DEST="$ROOT/LICENSES/${COMPONENT}-LICENSE.txt"
LICENSE_VENDORED=""
for cand in LICENSE LICENSE.txt LICENSE.md COPYING; do
  if [[ -f "$VENDORED_PATH/$cand" ]]; then
    LICENSE_VENDORED="$VENDORED_PATH/$cand"
    break
  fi
done
[[ -n "$LICENSE_VENDORED" ]] || fail "LICENSE missing in vendored tree for $COMPONENT"
cp -f "$LICENSE_VENDORED" "$LICENSE_DEST"

write_sha256sums
write_tree_sha256sums
update_upstream_md "$COMPONENT" "$VERSION" "$COMMIT" "$IMPORT_DATE" "$LICENSE_NAME" "$COMPUTED"

rm -f "$ROOT/third_party/.gitkeep" 2>/dev/null || true
if compgen -G "$ROOT/LICENSES/*-LICENSE.txt" >/dev/null; then
  rm -f "$ROOT/LICENSES/.gitkeep" 2>/dev/null || true
fi

echo "import-upstream: SUCCESS — $COMPONENT @ $COMMIT -> $VENDORED_REL"
