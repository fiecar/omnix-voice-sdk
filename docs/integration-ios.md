# Omnix Voice iOS — consume OmnixVoiceSDK.xcframework (SDK-043)

## Artifact

Built on macOS (`ios/build-xcframework.sh`):

- `dist/OmnixVoiceSDK.xcframework`
- `dist/OmnixVoiceSDK-x.y.z.xcframework.zip` (+ `.sha256`)
- `dist/THIRD_PARTY_NOTICES.md` and `dist/LICENSES/` (must ship with the binary)

Module name: **OmnixVoiceSDK**. Deployment target: **iOS 15.0**.

```swift
import OmnixVoiceSDK

try OmnixVoice.shared.initialize(config: OmnixVoiceConfig(
    sipServer: "sip.example.com",
    sipUser: "user@example.com",
    sipPassword: "placeholder"
))
```

## Embed in Xcode

1. Add `OmnixVoiceSDK.xcframework` to the app target (**Frameworks, Libraries, and Embedded Content** → Embed & Sign).
2. Ensure the app’s iOS deployment target is ≥ 15.0.
3. Microphone usage description (`NSMicrophoneUsageDescription`) is required before live audio; not exercised by the consumer smoke compile test.

## Limits (honest)

| Capability | Status |
|------------|--------|
| Compile/link `import OmnixVoiceSDK` | Covered by `ios/consumer-smoke/` on macOS CI |
| Simulator init smoke | Optional; no real SIP |
| Physical iPhone | **NOT AVAILABLE** |
| Real SIP E2E (H-3) | **NOT AVAILABLE** |
