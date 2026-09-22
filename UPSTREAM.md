# Upstream Baseline

Placeholder — populated by SDK-003 / SDK-004 (Baresip / re import) and later
import tasks (OpenSSL SDK-066, optional libopus SDK-067).

## Planned baseline (frozen — Issue #1 §0.2 F-12)

| Component | Version | Commit |
|-----------|---------|--------|
| Baresip   | v4.11.0 | `3d30821f099925d24167f8a99e93ba4d1be98599` |
| re        | v4.11.0 | `ceefe9ff499aa1bcfb6255aff1737434dd385322` |

Machine-readable source of truth after import:

- `third_party/SOURCE_MANIFEST.json`
- `third_party/SHA256SUMS`
- `third_party/TREE_SHA256SUMS`

Do not download from floating branches (`main` / `master`).
Do not upgrade foundational dependencies without an approved Issue #1 change.
