# Upgrading Baresip, re, and other vendored components

`scripts/update-upstream.ps1` and `scripts/update-upstream.sh` do not choose a version. The lead approves the tag, commit, and archive SHA-256 through Issue #1 change control before anyone edits the manifest.

## Steps

1. Record the approved tag, full commit SHA, and archive SHA-256. Do not use a branch or a floating `main` download.
2. Edit that component's entry in `third_party/SOURCE_MANIFEST.json`. Leave `archiveSha256` empty only for a first import; after that a mismatch is a hard failure.
3. Run the wrapper. It calls `import-upstream`, which checks the tag against the commit, checks the archive commit id, checks SHA-256, and replaces the vendored tree only after those checks pass. It then runs `verify-third-party`.
   - Windows: `pwsh -File scripts/update-upstream.ps1 -Component baresip`
   - Linux CI: `scripts/update-upstream.sh baresip`
4. If an approved local patch is required, record it in `PATCHES.md` (component, reason, issue or PR, files, upstreamed or not). Do not edit `third_party/` by hand.
5. Regenerate `SBOM.json` with `scripts/generate-sbom.ps1` or `.sh` so the commit SHA in the SBOM matches the manifest.

`re`, `openssl`, and `ios-cmake` use the same wrapper and the same manifest. The script refuses a component name that is not in the manifest and exits before any download.

Approved pins today are in `third_party/SOURCE_MANIFEST.json` (Baresip and re `v4.11.0`). Do not change them in an upgrade document commit.
