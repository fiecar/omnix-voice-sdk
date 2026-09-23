# Omnix Voice SDK — toolchain pins

Exact versions for reproducible Android (and later iOS / React Native) builds.
**Gate H-2:** lead must approve the NDK and AGP pins in the SDK-030 PR before merge.

## Android (SDK-030)

| Component | Pinned version | Notes |
|-----------|----------------|-------|
| NDK | **29.0.14206865** (r29) | ≥ r28 required (16 KB page default). Side-by-side path: `$ANDROID_SDK_ROOT/ndk/29.0.14206865`. |
| Android Gradle Plugin (AGP) | **8.9.1** | Exact pin (no `8.+`). compileSdk 36 floor. |
| Gradle (wrapper) | **8.11.1** | AGP 8.9.x compatibility table minimum. |
| JDK | **17** | AGP 8.9 requirement. |
| Kotlin | **2.0.21** | Android library + JNI stubs (SDK-031). Exact pin (no floating). |
| compileSdk | **36** | Library module only; host app owns `targetSdk`. |
| minSdk | **26** | AAudio / Omnix MVP floor. No support below 26. |
| ABIs | `arm64-v8a`, `armeabi-v7a`, `x86_64` | One `libomnixvoice.so` per ABI. |
| CMake | ≥ 3.22.1 | Via Android SDK CMake or NDK toolchain + host cmake/ninja. |
| ANDROID_STL | `c++_static` | Passed to CMake (`-DANDROID_STL=c++_static`). |
| STATIC | `ON` | Libre/baresip/OpenSSL static; only Omnix shared `.so` ships. |
| Visibility | `-fvisibility=hidden` | Public C API remains linkable within the same `.so` (JNI in SDK-031). |

### Module allowlist (shipped native)

`android/shipped-native-libs.txt` must contain exactly:

```
libomnixvoice.so
```

No `libssl.so` / `libcrypto.so` / `libc++_shared.so` in the AAR (OpenSSL and libc++ are static).

### Baresip modules (Android static embed)

Configured in `cpp/CMakeLists.txt` (`OMNIX_BARESIP_MODULES`). MVP audio uses **opensles** (minSdk 26). Upstream **aaudio** module requires API-28-only symbols and stays deferred until a future task revisits it without raising minSdk. After SDK-028: `stun` included. Opus only after SDK-067.

### OpenSSL (SDK-066)

Pinned OpenSSL **3.5.8** static libs per ABI under `build/openssl-android/<abi>/` (CI artifact or `scripts/fetch-openssl-android.ps1`). Never system OpenSSL for Android artifacts.

### Release AAR packaging (SDK-036)

`.\gradlew.bat assembleRelease` produces:

```
android/build/outputs/aar/OmnixVoiceSDK-0.1.0.aar
```

(version = `android/build.gradle.kts` `version`). The AAR must contain
`jni/{arm64-v8a,armeabi-v7a,x86_64}/libomnixvoice.so`, `classes.jar`,
`AndroidManifest.xml`, and `assets/THIRD_PARTY_NOTICES.md` (copied from repo
root at build time). No unlisted `.so` files.

### ABI verification (SDK-037)

```powershell
pwsh -File scripts/verify-abi.ps1 -Aar android/build/outputs/aar/OmnixVoiceSDK-0.1.0.aar
```

```bash
scripts/verify-abi.sh android/build/outputs/aar/OmnixVoiceSDK-*.aar
```

Both scripts require `jni/{arm64-v8a,armeabi-v7a,x86_64}/libomnixvoice.so` and
exit non-zero if any ABI is missing. CI calls the `.sh` after `assembleRelease`.

### 16 KB page-size verification (SDK-038)

Every `.so` inside the release AAR (any path) is inventoried against
`android/shipped-native-libs.txt`. For each library, **every** `PT_LOAD`
`Align` must be ≥ `0x4000` and a power of two; `GNU_RELRO` end
(`VirtAddr + MemSiz`) must be a multiple of 16384. `armeabi-v7a` violations
are `WARN (32-bit, informational)` only; `arm64-v8a` / `x86_64` violations
**FAIL**. Tooling uses the **pinned NDK** `llvm-readelf` (not system
`readelf`).

```powershell
$env:ANDROID_NDK_HOME = "$env:LOCALAPPDATA\Android\Sdk\ndk\29.0.14206865"
pwsh -File scripts/verify-16kb-alignment.ps1 -Aar android/build/outputs/aar/OmnixVoiceSDK-0.1.0.aar
```

```bash
export ANDROID_NDK_HOME="${ANDROID_SDK_ROOT}/ndk/29.0.14206865"
scripts/verify-16kb-alignment.sh android/build/outputs/aar/OmnixVoiceSDK-*.aar
```

APK zip alignment (AGP ≥ 8.5.1 / project AGP 8.9.1):

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\build-tools\35.0.0\zipalign.exe" -c -P 16 -v 4 `
  android/build/outputs/apk/androidTest/debug/OmnixVoiceSDK-debug-androidTest.apk
```

Runtime: `Omnix16KbPageTest` asserts `Os.sysconf(_SC_PAGESIZE) == 16384`,
loads `libomnixvoice.so`, and runs `initialize()` → `shutdown()`. On 4 KB
devices it **skips**. A 16 KB emulator/device (`adb shell getconf PAGE_SIZE`
→ `16384`) is a **manual release gate** when CI has no 16 KB image (also
tracked for SDK-065). Do **not** set `android:pageSizeCompat` to mask
failures.

### 16 KB defensive build invariant (SDK-038 lead-approved enforcement)

**Background:** NDK r28+ sets `PT_LOAD` alignment to `0x4000` via the ELF linker
script. However, the `android.toolchain.cmake` (non-legacy, used by AGP 8.x) does
**not** inject `-Wl,-z,max-page-size=16384` by default. LLD 21 (NDK r29) uses
4096-byte page size for `GNU_RELRO` end padding unless told otherwise — so the
RELRO end is aligned to 4 KB, not 16 KB, causing the SDK-038 validator to FAIL.

**Lead decision (2026-09-24):** After confirming NDK r29 + LLD 21 are the correct
pinned toolchain and that no 4 KB override exists, the lead explicitly authorised
adding these flags to the `omnixvoice` final shared-library target in
`android/CMakeLists.txt`:

```
-Wl,-z,max-page-size=16384
-Wl,-z,common-page-size=16384
```

**Why both flags are required:**
- `-z max-page-size=16384` — instructs LLD to round up the `GNU_RELRO` end to a
  16 KB boundary. Required for `(VirtAddr + MemSiz) % 0x4000 == 0`.
- `-z common-page-size=16384` — aligns common-section (BSS/data) allocations to
  16 KB, preventing underaligned load addresses on 16 KB devices.

**Affected target:** `omnixvoice` (produces `libomnixvoice.so`) in
`android/CMakeLists.txt` only. Scoped to `if(ANDROID)`.

**This is not a workaround.** It is an explicit defensive build invariant required
for Omnix Android artifacts to be 16 KB page-compatible as mandated by
[Android guidance](https://developer.android.com/guide/practices/page-sizes).
The validator (`scripts/verify-16kb-alignment.ps1 / .sh`) and its strict
semantics remain unchanged.

**Verification:**
```powershell
# After clean assembleRelease:
& llvm-readelf.exe -lW android/build/intermediates/cxx/RelWithDebInfo/.../arm64-v8a/libomnixvoice.so | Select-String RELRO
# VirtAddr + MemSiz must be a multiple of 0x4000
```

### Build commands

```powershell
# Windows (no WSL)
cd android
.\gradlew.bat assembleRelease
tar -tf build/outputs/aar/OmnixVoiceSDK-0.1.0.aar | Select-String '\.so$|classes\.jar|THIRD_PARTY_NOTICES|AndroidManifest'
```

```bash
# Linux/macOS CI
cd android && ./gradlew assembleRelease
unzip -l build/outputs/aar/OmnixVoiceSDK-*.aar | grep -E '\.so|classes|THIRD_PARTY_NOTICES|AndroidManifest'
```

NDK cross-compile without Gradle (developer smoke):

```powershell
$env:ANDROID_NDK_HOME = "$env:LOCALAPPDATA\Android\Sdk\ndk\29.0.14206865"
pwsh -File scripts/fetch-openssl-android.ps1   # once, checksum-verified
# Shared library is produced by the android/ Gradle+CMake path (SDK-030).
```

## iOS

**[MACOS REQUIRED]** — pins recorded when SDK-039 lands.

## React Native

Gate **H-1** (SDK-046): lead pins RN + matching AGP/Gradle in this file before that task starts.
