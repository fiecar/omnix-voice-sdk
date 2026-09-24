// Omnix Voice — public delegate (Issue #1 §20A.5). SDK-041.
// Method names: registrationStateChanged, incomingCall, callStateChanged,
// audioRouteChanged, didReceiveError. No credentials in payloads.

import Foundation

public protocol OmnixVoiceDelegate: AnyObject {
    func registrationStateChanged(
        _ state: OmnixRegistrationState,
        sipCode: Int?,
        reason: String?
    )

    func incomingCall(_ call: OmnixCallInfo)

    func callStateChanged(_ call: OmnixCallInfo)

    func audioRouteChanged(_ route: OmnixAudioRoute)

    func didReceiveError(_ code: OmnixErrorCode, detail: String?, callId: String?)
}

public extension OmnixVoiceDelegate {
    func registrationStateChanged(
        _ state: OmnixRegistrationState,
        sipCode: Int?,
        reason: String?
    ) {}

    func incomingCall(_ call: OmnixCallInfo) {}

    func callStateChanged(_ call: OmnixCallInfo) {}

    func audioRouteChanged(_ route: OmnixAudioRoute) {}

    func didReceiveError(_ code: OmnixErrorCode, detail: String?, callId: String?) {}
}
