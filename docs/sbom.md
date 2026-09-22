# Software Bill of Materials (SBOM)

## Purpose

`SBOM.json` is the repository SPDX 2.3 baseline describing components that
**currently exist** in this repository (Omnix Voice SDK + vendored upstreams
recorded in `third_party/SOURCE_MANIFEST.json`).

## Format

- Format: **SPDX 2.3 JSON**
- Output path: `SBOM.json` (repository root) — frozen by Issue #2 SDK-008

## Generator

| Field | Value |
|-------|-------|
| Tool | [syft](https://github.com/anchore/syft) |
| Pinned version | **1.52.0** |
| Tool license | Apache-2.0 |
| Enrichment | `scripts/enrich-sbom.js` injects version, commit SHA, and license from `SOURCE_MANIFEST.json` |

Do not commit syft binaries. Scripts download the pinned release into a local
cache (`%LOCALAPPDATA%\omnix-voice-sdk\tools\syft\...` on Windows).

## Windows generation

```powershell
pwsh -File scripts/generate-sbom.ps1
pwsh -File scripts/verify-sbom.ps1
```

## Linux/macOS CI

```bash
scripts/generate-sbom.sh
scripts/verify-sbom.sh
```

## Relationships

```
omnix-voice-sdk
  └── DEPENDS_ON → baresip (v4.11.0 @ 3d30821f…)
        └── DEPENDS_ON → re (v4.11.0 @ ceefe9ff…)
```

Planned-but-absent components (OpenSSL, libopus, React Native) are **not**
listed as current SBOM packages until imported/pinned.

## When to regenerate

Regenerate `SBOM.json` when:

- a dependency is added, removed, or version-changed
- a vendored upstream tree changes (import / approved patch)
- preparing a release

## Reproducibility note

Generation pins syft **1.52.0** and rewrites `documentNamespace` /
`creationInfo` to stable values via `enrich-sbom.js`. Package identity
(names, versions, commits, licenses, relationships) is asserted by
`verify-sbom`. Re-run twice locally if regenerating after a dependency change.
