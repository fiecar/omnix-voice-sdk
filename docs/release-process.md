# Release process

Current package version is **0.1.0**. A release tag is `v` plus the semver (`v0.1.0`). The first stable tag uses the same form (`v1.0.0`).

## Version files

Bump these to the same semver in one commit before tagging:

| File | Field |
|------|--------|
| `android/build.gradle.kts` | `version` (AAR / Maven coordinate `com.omnix.voice:omnix-voice-sdk`) |
| `react-native/package.json` | `version` |
| `cpp/CMakeLists.txt` | `project(omnix_voice_native ...)` `VERSION` |

`react-native/omnix-voice-sdk.podspec` reads `package.json`, so it follows that file. Today `cpp/CMakeLists.txt` has no `VERSION` argument; the release commit adds one that matches the other two files.

Do not bump OpenSSL, Baresip, re, NDK, AGP, or React Native as part of an SDK version bump.

## Changelog

Add a `CHANGELOG.md` section for the version: added, changed, fixed, and security notes. Do not include credentials, customer names, hostnames, or IP addresses.

## Tag and CI

SDK-062 owns `.github/workflows/release.yml`. That workflow is not in the tree yet. When it lands, it runs on tags matching `v*.*.*` and attaches the AAR, npm tarball, XCFramework zip (when packaging succeeds), `THIRD_PARTY_NOTICES.md`, `SBOM.json`, and `SHA256SUMS`.

Until that workflow is merged, do not push a release tag. iOS XCFramework packaging is blocked (SDK-043, PR #42). A tag must not claim an XCFramework artifact that was not produced.

## Checklist

1. Version files above match.
2. `CHANGELOG.md` has the version section.
3. `pwsh -File scripts/check-licenses.ps1` passes.
4. Android CI (OpenSSL static, native ctest, 16 KB checks, Gradle) is green on the commit.
5. Tag `vX.Y.Z` on that commit and push the tag only after `release.yml` exists.
