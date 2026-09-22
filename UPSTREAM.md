# Upstream Baseline

Human-readable mirror of `third_party/SOURCE_MANIFEST.json` (the machine-readable
source of truth). Do not download from floating branches (`main` / `master`).
Do not upgrade foundational dependencies without an approved Issue #1 change.

## Current imports

Baresip: tag=v4.11.0, commit=3d30821f099925d24167f8a99e93ba4d1be98599, release=2026-08-25, imported=2026-09-23, license=BSD-3-Clause, archive-sha256=148d0c743a71af19a436dba17c5d33a881e1c5e250ab100cf6b4729f0c7aa82c

re: tag=v4.11.0, commit=ceefe9ff499aa1bcfb6255aff1737434dd385322, release=2026-08-25, imported=2026-09-23, license=BSD-3-Clause, archive-sha256=a74a96cddb0284261dcdb6ca7728dd1609549e576075fa192f289e1abf523faa

OpenSSL: (from SDK-066)

## Machine-readable provenance

| Artifact | Role |
|----------|------|
| `third_party/SOURCE_MANIFEST.json` | Source of truth (version, commit, archive SHA-256, import date, license) |
| `third_party/SHA256SUMS` | SHA-256 of downloaded source archives |
| `third_party/TREE_SHA256SUMS` | SHA-256 of every file in each vendored tree |
| `PATCHES.md` | Approved local modifications only (MVP expectation: empty) |
| `SBOM.json` | SPDX 2.3 bill of materials (regenerate after import) |

## Update procedure

Numbered steps from Issue #1 §13 “Upgrade Procedure”:

1. Lead architect approves the new version in Issue #1 (change control §0.3). **Executors never upgrade ad hoc.**
2. Review upstream changelog for breaking API changes.
3. Edit `SOURCE_MANIFEST.json`: new `version`, new `commit`, empty `archiveSha256`.
4. Run `scripts/import-upstream.ps1 -Component <name>` (Windows) or `scripts/import-upstream.sh <name>` (Linux/macOS/CI). Convenience wrappers: `scripts/update-upstream.ps1` / `scripts/update-upstream.sh`.
5. Script downloads by commit, verifies tag→commit, records SHA-256, replaces the vendored tree atomically.
6. Re-apply all entries in `PATCHES.md`.
7. Run `scripts/verify-third-party`, license scan, SBOM regeneration (`scripts/generate-sbom` + `scripts/verify-sbom`).
8. Build, test, release.
