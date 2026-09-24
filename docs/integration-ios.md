# Omnix Voice iOS — consume OmnixVoiceSDK.xcframework (SDK-043)

## Artifact

Built on macOS (`ios/build-xcframework.sh`):

- `dist/OmnixVoiceSDK.xcframework`
- `dist/OmnixVoiceSDK-x.y.z.xcframework.zip` (+ `.sha256`)
- `dist/THIRD_PARTY_NOTICES.md` and `dist/LICENSES/` (must ship with the binary)

Module name: **OmnixVoiceSDK**. Deployment target: **iOS 15.0**.

```swift
import OmnixVoiceSDK

let bridge = OmnixVoiceBridge.shared
// Swift OmnixVoice facade: compile ios/Sources/OmnixVoice/*.swift in the app
// until a future BUILD_LIBRARY_FOR_DISTRIBUTION Swift binary lands.
_ = bridge.isInitialized
```

## Embed in Xcode

1. Add `OmnixVoiceSDK.xcframework` to the app target.
2. Link system frameworks/libs used by the static archive: Foundation, AVFoundation, AudioToolbox, CoreAudio, Security, SystemConfiguration, CFNetwork, CoreMedia, UIKit, `resolv`, `c++`, `z`.
3. Deployment target ≥ 15.0.
4. Swift facade (`OmnixVoice` class) is **source** in the SDK repo (`ios/Sources/OmnixVoice`); MVP binary module exposes the ObjC bridge (`import OmnixVoiceSDK` → `OmnixVoiceBridge`).
5. Microphone usage description (`NSMicrophoneUsageDescription`) is required before live audio.

## Limits (honest)

| Capability | Status |
|------------|--------|
| Compile/link `import OmnixVoiceSDK` | Covered by `ios/consumer-smoke/` on macOS CI |
| Simulator init smoke | Optional; no real SIP |
| Physical iPhone | **NOT AVAILABLE** |
| Real SIP E2E (H-3) | **NOT AVAILABLE** |
