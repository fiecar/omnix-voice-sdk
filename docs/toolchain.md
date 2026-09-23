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

### Build commands

```powershell
# Windows (no WSL)
cd android
.\gradlew.bat assembleRelease
```

```bash
# Linux/macOS CI
cd android && ./gradlew assembleRelease
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
