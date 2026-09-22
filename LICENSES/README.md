# LICENSES

Verbatim copies of upstream license texts. These files MUST accompany binary
distributions of the Omnix Voice SDK (see also `THIRD_PARTY_NOTICES.md`).

| File | Upstream source | License |
|------|-----------------|---------|
| `baresip-LICENSE.txt` | `third_party/baresip/LICENSE` | BSD-3-Clause |
| `re-LICENSE.txt` | `third_party/re/LICENSE` | BSD-3-Clause |

Do **not** edit these files by hand. Refresh only by re-copying from the
vendored trees (or via `scripts/import-upstream`), then confirm SHA-256 equality:

```powershell
Copy-Item third_party/baresip/LICENSE LICENSES/baresip-LICENSE.txt
Copy-Item third_party/re/LICENSE LICENSES/re-LICENSE.txt
(Get-FileHash third_party/baresip/LICENSE).Hash -eq (Get-FileHash LICENSES/baresip-LICENSE.txt).Hash
(Get-FileHash third_party/re/LICENSE).Hash -eq (Get-FileHash LICENSES/re-LICENSE.txt).Hash
```

`openssl-LICENSE.txt` is added when OpenSSL is imported (SDK-066).
Opus license text is added only if libopus is included (SDK-067).

## SDK-006 verification

- License files confirmed byte-identical to upstream `LICENSE` via SHA-256.
- Copyright headers confirmed present in 5+ source files under each of
  `third_party/baresip/` and `third_party/re/`.
- No copyright headers removed or modified (`scripts/verify-third-party` passes).
