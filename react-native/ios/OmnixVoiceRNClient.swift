import Foundation
import OmnixVoice

/// Forwards public OmnixVoice events into the React Native module.
/// The module is the only caller. It does not touch the upstream SIP stack.
@objc(OmnixVoiceRNEventSink)
public protocol OmnixVoiceRNEventSink: AnyObject {
    @objc(rnRegistrationStateChanged:sipCode:reason:)
    func rnRegistrationStateChanged(_ state: String, sipCode: NSNumber?, reason: String?)

    @objc(rnIncomingCall:)
    func rnIncomingCall(_ call: NSDictionary)

    @objc(rnCallStateChanged:)
    func rnCallStateChanged(_ call: NSDictionary)

    @objc(rnAudioRouteChanged:)
    func rnAudioRouteChanged(_ route: String)

    @objc(rnError:detail:callId:)
    func rnError(_ code: String, detail: String?, callId: String?)
}

/// Objective-C surface over the public Swift OmnixVoice API (SDK-049).
@objc(OmnixVoiceRNClient)
public final class OmnixVoiceRNClient: NSObject, OmnixVoiceDelegate {
    @objc public static let shared = OmnixVoiceRNClient()
    @objc public weak var eventSink: OmnixVoiceRNEventSink?

    private override init() {
        super.init()
    }

    @objc(initializeWithSipServer:sipUser:sipPassword:authUser:displayName:stunServer:verifyCert:enableSrtp:codecs:errorCode:errorDetail:)
    public func initializeWithSipServer(
        _ sipServer: String,
        sipUser: String,
        sipPassword: String,
        authUser: String?,
        displayName: String?,
        stunServer: String?,
        verifyCert: Bool,
        enableSrtp: Bool,
        codecs: String?,
        errorCode: AutoreleasingUnsafeMutablePointer<NSString?>?,
        errorDetail: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        let config = OmnixVoiceConfig(
            sipServer: sipServer,
            sipUser: sipUser,
            sipPassword: sipPassword,
            authUser: emptyToNil(authUser),
            displayName: emptyToNil(displayName),
            stunServer: emptyToNil(stunServer),
            verifyCert: verifyCert,
            enableSrtp: enableSrtp,
            codecs: parseCodecs(codecs)
        )
        OmnixVoice.shared.delegate = self
        do {
            try OmnixVoice.shared.initialize(config: config)
            return true
        } catch {
            if let voice = error as? OmnixVoiceError, voice.code != .INVALID_CALL_STATE {
                if OmnixVoice.shared.delegate === self {
                    OmnixVoice.shared.delegate = nil
                }
            }
            return fail(error, codeOut: errorCode, detailOut: errorDetail, secret: sipPassword)
        }
    }

    @objc(shutdownClient)
    public func shutdownClient() {
        if OmnixVoice.shared.delegate === self {
            OmnixVoice.shared.delegate = nil
        }
        OmnixVoice.shared.shutdown()
    }

    @objc(registerAccountWithErrorCode:errorDetail:)
    public func registerAccount(
        errorCode: AutoreleasingUnsafeMutablePointer<NSString?>?,
        errorDetail: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        perform(errorCode, errorDetail) { try OmnixVoice.shared.register() }
    }

    @objc(unregisterAccount)
    public func unregisterAccount() {
        OmnixVoice.shared.unregister()
    }

    @objc(makeCall:errorCode:errorDetail:)
    public func makeCall(
        _ destination: String,
        errorCode: AutoreleasingUnsafeMutablePointer<NSString?>?,
        errorDetail: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> String? {
        do {
            return try OmnixVoice.shared.makeCall(destination: destination)
        } catch {
            _ = fail(error, codeOut: errorCode, detailOut: errorDetail, secret: nil)
            return nil
        }
    }

    @objc(answerCall:errorCode:errorDetail:)
    public func answerCall(
        _ callId: String,
        errorCode: AutoreleasingUnsafeMutablePointer<NSString?>?,
        errorDetail: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        perform(errorCode, errorDetail) { try OmnixVoice.shared.answerCall(callId: callId) }
    }

    @objc(rejectCall:errorCode:errorDetail:)
    public func rejectCall(
        _ callId: String,
        errorCode: AutoreleasingUnsafeMutablePointer<NSString?>?,
        errorDetail: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        perform(errorCode, errorDetail) { try OmnixVoice.shared.rejectCall(callId: callId) }
    }

    @objc(hangupCall:errorCode:errorDetail:)
    public func hangupCall(
        _ callId: String,
        errorCode: AutoreleasingUnsafeMutablePointer<NSString?>?,
        errorDetail: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        perform(errorCode, errorDetail) { try OmnixVoice.shared.hangupCall(callId: callId) }
    }

    @objc(holdCall:errorCode:errorDetail:)
    public func holdCall(
        _ callId: String,
        errorCode: AutoreleasingUnsafeMutablePointer<NSString?>?,
        errorDetail: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        perform(errorCode, errorDetail) { try OmnixVoice.shared.holdCall(callId: callId) }
    }

    @objc(resumeCall:errorCode:errorDetail:)
    public func resumeCall(
        _ callId: String,
        errorCode: AutoreleasingUnsafeMutablePointer<NSString?>?,
        errorDetail: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        perform(errorCode, errorDetail) { try OmnixVoice.shared.resumeCall(callId: callId) }
    }

    @objc(setMuted:callId:errorCode:errorDetail:)
    public func setMuted(
        _ muted: Bool,
        callId: String,
        errorCode: AutoreleasingUnsafeMutablePointer<NSString?>?,
        errorDetail: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        perform(errorCode, errorDetail) { try OmnixVoice.shared.setMuted(callId: callId, muted: muted) }
    }

    @objc(setSpeakerEnabled:errorCode:errorDetail:)
    public func setSpeakerEnabled(
        _ enabled: Bool,
        errorCode: AutoreleasingUnsafeMutablePointer<NSString?>?,
        errorDetail: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        perform(errorCode, errorDetail) { try OmnixVoice.shared.setSpeakerEnabled(enabled) }
    }

    @objc(sendDTMF:digit:errorCode:errorDetail:)
    public func sendDTMF(
        _ callId: String,
        digit: String,
        errorCode: AutoreleasingUnsafeMutablePointer<NSString?>?,
        errorDetail: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        guard digit.count == 1, let character = digit.first else {
            errorCode?.pointee = OmnixErrorCode.INVALID_CONFIGURATION.rawValue as NSString
            errorDetail?.pointee = "DTMF digit must be one character"
            return false
        }
        return perform(errorCode, errorDetail) {
            try OmnixVoice.shared.sendDTMF(callId: callId, digit: character)
        }
    }

    @objc(transferCall:destination:errorCode:errorDetail:)
    public func transferCall(
        _ callId: String,
        destination: String,
        errorCode: AutoreleasingUnsafeMutablePointer<NSString?>?,
        errorDetail: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        perform(errorCode, errorDetail) {
            try OmnixVoice.shared.transferCall(callId: callId, destination: destination)
        }
    }

    @objc(currentRegistrationState)
    public func currentRegistrationState() -> String {
        OmnixVoice.shared.registrationState.rawValue
    }

    public func registrationStateChanged(
        _ state: OmnixRegistrationState,
        sipCode: Int?,
        reason: String?
    ) {
        eventSink?.rnRegistrationStateChanged(
            state.rawValue,
            sipCode: sipCode.map { NSNumber(value: $0) },
            reason: scrub(reason, secret: nil)
        )
    }

    public func incomingCall(_ call: OmnixCallInfo) {
        eventSink?.rnIncomingCall(callPayload(call))
    }

    public func callStateChanged(_ call: OmnixCallInfo) {
        eventSink?.rnCallStateChanged(callPayload(call))
    }

    public func audioRouteChanged(_ route: OmnixAudioRoute) {
        eventSink?.rnAudioRouteChanged(route.rawValue)
    }

    public func didReceiveError(_ code: OmnixErrorCode, detail: String?, callId: String?) {
        eventSink?.rnError(code.rawValue, detail: scrub(detail, secret: nil), callId: callId)
    }

    private func perform(
        _ errorCode: AutoreleasingUnsafeMutablePointer<NSString?>?,
        _ errorDetail: AutoreleasingUnsafeMutablePointer<NSString?>?,
        _ body: () throws -> Void
    ) -> Bool {
        do {
            try body()
            return true
        } catch {
            return fail(error, codeOut: errorCode, detailOut: errorDetail, secret: nil)
        }
    }

    private func fail(
        _ error: Error,
        codeOut: AutoreleasingUnsafeMutablePointer<NSString?>?,
        detailOut: AutoreleasingUnsafeMutablePointer<NSString?>?,
        secret: String?
    ) -> Bool {
        let voice = (error as? OmnixVoiceError) ?? OmnixVoiceError(
            code: .INTERNAL_NATIVE_ERROR,
            detail: nil
        )
        codeOut?.pointee = voice.code.rawValue as NSString
        detailOut?.pointee = scrub(voice.detail, secret: secret) as NSString?
        return false
    }

    private func callPayload(_ call: OmnixCallInfo) -> NSDictionary {
        [
            "callId": call.callId,
            "peerUri": call.peerUri,
            "peerDisplayName": call.peerDisplayName,
            "state": call.state.rawValue,
            "isOutgoing": NSNumber(value: call.isOutgoing),
            "isMuted": NSNumber(value: call.isMuted),
            "isOnHold": NSNumber(value: call.isOnHold),
        ]
    }

    private func parseCodecs(_ raw: String?) -> [OmnixCodec] {
        let fallback: [OmnixCodec] = [.opus, .pcmu, .pcma]
        guard let raw, !raw.isEmpty else {
            return fallback
        }
        let parsed = raw.split(separator: ",").compactMap { token -> OmnixCodec? in
            OmnixCodec(rawValue: token.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return parsed.isEmpty ? fallback : parsed
    }

    private func emptyToNil(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
    }

    private func scrub(_ detail: String?, secret: String?) -> String? {
        guard var out = detail, !out.isEmpty else {
            return nil
        }
        if let secret, !secret.isEmpty {
            out = out.replacingOccurrences(of: secret, with: "[REDACTED]")
        }
        if let regex = try? NSRegularExpression(
            pattern: "(?i)((?:sipPassword|auth_pass|password)\\s*[:=]\\s*)(\\S+)"
        ) {
            let range = NSRange(out.startIndex..<out.endIndex, in: out)
            out = regex.stringByReplacingMatches(in: out, range: range, withTemplate: "$1[REDACTED]")
        }
        if out.count > 180 {
            out = String(out.prefix(180))
        }
        return out
    }
}
