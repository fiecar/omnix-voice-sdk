// SDK-043 consumer smoke — compile/link only. No SIP / mic / CallKit.
// Placeholders only.
import Foundation
import OmnixVoiceSDK

let shared = OmnixVoice.shared
let state = shared.registrationState
// ObjC bridge class property: existing facade uses `.shared` (SDK-041).
let bridge = OmnixVoiceBridge.shared
_ = bridge.isInitialized
print("OmnixConsumerSmoke: import OmnixVoiceSDK OK state=\(state)")
