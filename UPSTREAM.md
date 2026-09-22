# Upstream Baseline

Human-readable mirror of `third_party/SOURCE_MANIFEST.json` (the machine-readable
source of truth). Do not download from floating branches (`main` / `master`).
Do not upgrade foundational dependencies without an approved Issue #1 change.

## Current imports

Baresip: tag=v4.11.0, commit=3d30821f099925d24167f8a99e93ba4d1be98599, release=2026-08-25, imported=2026-09-23, license=BSD-3-Clause, archive-sha256=148d0c743a71af19a436dba17c5d33a881e1c5e250ab100cf6b4729f0c7aa82c

re: tag=v4.11.0, commit=ceefe9ff499aa1bcfb6255aff1737434dd385322, release=2026-08-25, imported=2026-09-23, license=BSD-3-Clause, archive-sha256=a74a96cddb0284261dcdb6ca7728dd1609549e576075fa192f289e1abf523faa

OpenSSL: tag=openssl-3.5.8, commit=f4dc4d58b48d346a8270183f89acf826d459b0ca, release=2026-08-25, imported=2026-09-23, license=Apache-2.0, archive-sha256=14067f511684d80698ffe97b8ad7989b9271ef6eef1b4b115cb00966c13e89d3

<!-- IMPORT:baresip -->
baresip: tag=v4.11.0, commit=3d30821f099925d24167f8a99e93ba4d1be98599, imported=2026-09-23, license=BSD-3-Clause, archive-sha256=148d0c743a71af19a436dba17c5d33a881e1c5e250ab100cf6b4729f0c7aa82c

<!-- IMPORT:re -->
re: tag=v4.11.0, commit=ceefe9ff499aa1bcfb6255aff1737434dd385322, imported=2026-09-23, license=BSD-3-Clause, archive-sha256=a74a96cddb0284261dcdb6ca7728dd1609549e576075fa192f289e1abf523faa

<!-- IMPORT:openssl -->
openssl: tag=openssl-3.5.8, commit=f4dc4d58b48d346a8270183f89acf826d459b0ca, imported=2026-09-23, license=Apache-2.0, archive-sha256=14067f511684d80698ffe97b8ad7989b9271ef6eef1b4b115cb00966c13e89d3

## Machine-readable provenance

| Artifact | Role |
|----------|------|
| `third_party/SOURCE_MANIFEST.json` | Source of truth (version, commit, archive SHA-256, import date, license) |
| `third_party/SHA256SUMS` | SHA-256 of downloaded source archives |
| `third_party/TREE_SHA256SUMS` | SHA-256 of every file in each vendored tree |
| `PATCHES.md` | Approved local modifications only (MVP expectation: empty) |
| `SBOM.json` | SPDX 2.3 bill of materials (regenerate after import) |

## Android static OpenSSL (SDK-066)

- Canonical build: Linux CI (`.github/workflows/android.yml`) via `scripts/build-openssl-android.sh`
- Windows fetch (no WSL): `pwsh -File scripts/fetch-openssl-android.ps1` (checksum-verified CI artifact)
- NDK for this job: **r29** (`29.0.14206865` via setup-ndk) — provisional until human gate H-2 / SDK-030 pins the Android module NDK/AGP
- Output: static `libssl.a` / `libcrypto.a` only (`no-shared`); never ship `.so`

## Update procedure

Numbered steps from Issue #1 section 13 "Upgrade Procedure":

1. Lead architect approves the new version in Issue #1 (change control section 0.3). **Executors never upgrade ad hoc.**
2. Review upstream changelog for breaking API changes.
3. Edit `SOURCE_MANIFEST.json`: new `version`, new `commit`, empty `archiveSha256`.
4. Run `scripts/import-upstream.ps1 -Component <name>` (Windows) or `scripts/import-upstream.sh <name>` (Linux/macOS/CI). Convenience wrappers: `scripts/update-upstream.ps1` / `scripts/update-upstream.sh`.
5. Script downloads by commit, verifies tag to commit, records SHA-256, replaces the vendored tree atomically.
6. Re-apply all entries in `PATCHES.md`.
7. Run `scripts/verify-third-party`, license scan, SBOM regeneration (`scripts/generate-sbom` + `scripts/verify-sbom`).
8. Build, test, release.
