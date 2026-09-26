# Omnix Voice SDK

React Native voice SDK (Android and iOS) with an Omnix public API.
Host apps do not call Baresip, re, JNI, or Objective-C bridge types.

Architecture and the frozen API are in
[Issue #1](https://github.com/fiecar/omnix-voice-sdk/issues/1).
Task status is in
[Issue #2](https://github.com/fiecar/omnix-voice-sdk/issues/2).

Package: `@omnix/voice-sdk` `0.1.0`. React Native **0.87.1**, Node **22.x**, New Architecture.
Android library: `minSdk` 26, `compileSdk` 36. The host app owns `targetSdk`.

## What is implemented

| Area | Status |
|------|--------|
| C facade, Android Kotlin SDK, iOS Swift facade (source) | IMPLEMENTED |
| Android 16 KB page-size check (SDK-038: ELF alignment + runtime initialize/shutdown on a 16 KB image) | IMPLEMENTED + VERIFIED in that task. This README does not re-run it. |
| `@omnix/voice-sdk` TypeScript API and Jest suite (mocked native module) | IMPLEMENTED |
| Android React Native TurboModule source (`OmnixVoiceModule`) | IMPLEMENTED. Host-app Gradle compile of that module is NOT YET VERIFIED. |
| iOS `OmnixVoiceSDK.xcframework` | BLOCKED (SDK-043). Static device/simulator libraries are not a packaged XCFramework. |
| Real SIP registration and calls | NOT AVAILABLE (no test server) |
| Physical iPhone | NOT AVAILABLE |
| Blind transfer | Public `transferCall` exists and rejects `NOT_SUPPORTED` until SDK-024 |
| Background, killed-app, or suspended incoming calls | POST-MVP. Not implemented. |
| CallKit, PushKit, FCM, ConnectionService, foreground-service telephony | POST-MVP documentation only |

Incoming calls in the MVP are only while the process is alive, the SDK is initialized and registered, and the app is in the foreground.

The host app stores SIP credentials. The SDK does not persist `sipPassword` and must not log it.

## Layout

- `cpp/` — C facade. Public headers are `cpp/include/omnix_voice/`.
- `android/` — Kotlin SDK and JNI. Public package `com.omnix.voice`.
- `ios/Sources/OmnixVoice/` — Swift facade.
- `react-native/` — `@omnix/voice-sdk`.
- `docs/architecture.md` — layering diagram.
- `docs/api-reference.md` — public functions.
- `docs/integration-android.md` — Android host permissions and audio.
- `THIRD_PARTY_NOTICES.md` and `LICENSES/` — attribution.

## License

Omnix source outside `third_party/` is the project license when published.
Vendored components keep their own licenses. See `THIRD_PARTY_NOTICES.md`.
