// SDK-043 consumer smoke — compile/link only. No SIP / mic / CallKit.
// Consumes the ObjC module packaged in OmnixVoiceSDK.xcframework.
import Foundation
import OmnixVoiceSDK

let bridge = OmnixVoiceBridge.shared
_ = bridge.isInitialized
print("OmnixConsumerSmoke: import OmnixVoiceSDK OK initialized=\(bridge.isInitialized)")
