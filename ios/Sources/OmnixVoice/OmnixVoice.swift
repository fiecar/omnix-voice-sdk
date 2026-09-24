// Omnix Voice — public Swift facade (Issue #1 §20A.1). SDK-041.
// Wraps OmnixVoiceBridge. Public API exposes no ObjC / Baresip / re types.
// Placeholders only; never log sipPassword.

import Foundation

public final class OmnixVoice {
    public static let shared = OmnixVoice()

    public weak var delegate: OmnixVoiceDelegate?

    private let lock = NSLock()
    private var audioRoute: OmnixAudioRoute = .UNKNOWN
    private let bridgeSink: BridgeSink

    private init() {
        bridgeSink = BridgeSink()
        bridgeSink.owner = self
        OmnixVoiceBridge.sharedBridge.delegate = bridgeSink
    }

    public var registrationState: OmnixRegistrationState {
        lock.lock()
        defer { lock.unlock() }
        let raw = Int(OmnixVoiceBridge.sharedBridge.registrationState.rawValue)
        return OmnixRegistrationState.fromBridge(raw)
    }

    public func initialize(config: OmnixVoiceConfig) throws {
        lock.lock()
        defer { lock.unlock() }

        let bridgeConfig = OmnixVoiceBridgeConfig()
        bridgeConfig.sipServer = config.sipServer
        bridgeConfig.sipUser = config.sipUser
        bridgeConfig.sipPassword = config.sipPassword
        bridgeConfig.authUser = config.authUser
        bridgeConfig.displayName = config.displayName
        bridgeConfig.stunServer = config.stunServer
        bridgeConfig.verifyCert = config.verifyCert
        bridgeConfig.enableSrtp = config.enableSrtp
        if !config.codecs.isEmpty {
            bridgeConfig.codecs = config.codecs.map(\.wireName).joined(separator: ",")
        }

        var error: NSError?
        let ok = OmnixVoiceBridge.sharedBridge.initialize(with: bridgeConfig, error: &error)
        if !ok {
            throw mapBridgeError(error)
        }
    }

    public func shutdown() {
        lock.lock()
        defer { lock.unlock() }
        OmnixVoiceBridge.sharedBridge.shutdown()
        audioRoute = .UNKNOWN
    }

    public func register() throws {
        lock.lock()
        defer { lock.unlock() }
        var error: NSError?
        let ok = OmnixVoiceBridge.sharedBridge.registerAndReturnError(&error)
        if !ok {
            throw mapBridgeError(error)
        }
    }

    public func unregister() {
        lock.lock()
        defer { lock.unlock() }
        OmnixVoiceBridge.sharedBridge.unregister()
    }

    public func makeCall(destination: String) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        var callId: NSString?
        var error: NSError?
        let ok = OmnixVoiceBridge.sharedBridge.makeCall(
            destination,
            callId: &callId,
            error: &error
        )
        if !ok {
            throw mapBridgeError(error)
        }
        guard let id = callId as String?, !id.isEmpty else {
            throw OmnixVoiceError(code: .CALL_FAILED, detail: "makeCall failed")
        }
        return id
    }

    public func answerCall(callId: String) throws {
        try invokeCall(callId) { bridge, cid, err in
            bridge.answerCall(cid, error: err)
        }
    }

    public func rejectCall(callId: String) throws {
        try invokeCall(callId) { bridge, cid, err in
            bridge.rejectCall(cid, error: err)
        }
    }

    public func hangupCall(callId: String) throws {
        try invokeCall(callId) { bridge, cid, err in
            bridge.hangupCall(cid, error: err)
        }
    }

    public func holdCall(callId: String) throws {
        try invokeCall(callId) { bridge, cid, err in
            bridge.holdCall(cid, error: err)
        }
    }

    public func resumeCall(callId: String) throws {
        try invokeCall(callId) { bridge, cid, err in
            bridge.resumeCall(cid, error: err)
        }
    }

    public func setMuted(callId: String, muted: Bool) throws {
        try invokeCall(callId) { bridge, cid, err in
            bridge.setMuted(muted, callId: cid, error: err)
        }
    }

    public func setSpeakerEnabled(_ enabled: Bool) throws {
        lock.lock()
        defer { lock.unlock() }
        var error: NSError?
        let ok = OmnixVoiceBridge.sharedBridge.setSpeakerEnabled(enabled, error: &error)
        if !ok {
            throw mapBridgeError(error)
        }
        audioRoute = enabled ? .SPEAKER : .EARPIECE
        let route = audioRoute
        let del = delegate
        DispatchQueue.main.async {
            del?.audioRouteChanged(route)
        }
    }

    public func sendDTMF(callId: String, digit: Character) throws {
        guard let scalar = digit.unicodeScalars.first, scalar.isASCII else {
            throw OmnixVoiceError(
                code: .INVALID_CONFIGURATION,
                detail: "DTMF digit out of range"
            )
        }
        let value = unichar(scalar.value)
        try invokeCall(callId) { bridge, cid, err in
            bridge.sendDTMF(value, callId: cid, error: err)
        }
    }

    /// Blind transfer stub until SDK-024. Always throws `NOT_SUPPORTED`.
    public func transferCall(callId: String, destination: String) throws {
        if callId.isEmpty || destination.isEmpty {
            throw OmnixVoiceError(
                code: .INVALID_CONFIGURATION,
                detail: "callId and destination are required"
            )
        }
        throw OmnixVoiceError(
            code: .NOT_SUPPORTED,
            detail: "blind transfer requires SDK-024"
        )
    }

    public func callInfo(callId: String) -> OmnixCallInfo? {
        lock.lock()
        defer { lock.unlock() }
        guard let info = OmnixVoiceBridge.sharedBridge.callInfo(forCallId: callId) else {
            return nil
        }
        return Self.mapCallInfo(info)
    }

    // MARK: - Internal

    private func invokeCall(
        _ callId: String,
        _ body: (OmnixVoiceBridge, String, NSErrorPointer) -> Bool
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        if callId.isEmpty {
            throw OmnixVoiceError(
                code: .INVALID_CONFIGURATION,
                detail: "callId is required"
            )
        }
        var error: NSError?
        let ok = body(OmnixVoiceBridge.sharedBridge, callId, &error)
        if !ok {
            throw mapBridgeError(error)
        }
    }

    private func mapBridgeError(_ error: NSError?) -> OmnixVoiceError {
        let code = OmnixErrorCode.fromNative(error?.code ?? 17)
        return OmnixVoiceError(code: code, detail: error?.localizedDescription)
    }

    fileprivate static func mapCallInfo(_ info: OmnixVoiceBridgeCallInfo) -> OmnixCallInfo {
        OmnixCallInfo(
            callId: info.callId,
            peerUri: info.peerUri,
            peerDisplayName: info.peerDisplayName,
            state: OmnixCallState.fromBridge(Int(info.state.rawValue)),
            isOutgoing: info.isOutgoing,
            isMuted: info.isMuted,
            isOnHold: info.isOnHold
        )
    }

    fileprivate func emitRegistration(
        state: OmnixRegistrationState,
        sipCode: Int?,
        reason: String?
    ) {
        delegate?.registrationStateChanged(state, sipCode: sipCode, reason: reason)
    }

    fileprivate func emitIncoming(_ call: OmnixCallInfo) {
        delegate?.incomingCall(call)
    }

    fileprivate func emitCallState(_ call: OmnixCallInfo) {
        delegate?.callStateChanged(call)
    }

    fileprivate func emitError(code: OmnixErrorCode, detail: String?) {
        delegate?.didReceiveError(code, detail: detail, callId: nil)
    }
}

/// ObjC bridge → Swift delegate adapter (not part of the public API).
private final class BridgeSink: NSObject, OmnixVoiceBridgeDelegate {
    weak var owner: OmnixVoice?

    func omnixVoiceBridge(
        _ bridge: OmnixVoiceBridge,
        registrationStateChanged state: OmnixBridgeRegistrationState,
        sipCode: Int,
        reason: String?
    ) {
        let mapped = OmnixRegistrationState.fromBridge(Int(state.rawValue))
        let code: Int? = sipCode == 0 ? nil : sipCode
        owner?.emitRegistration(state: mapped, sipCode: code, reason: reason)
    }

    func omnixVoiceBridge(_ bridge: OmnixVoiceBridge, incomingCall call: OmnixVoiceBridgeCallInfo) {
        owner?.emitIncoming(OmnixVoice.mapCallInfo(call))
    }

    func omnixVoiceBridge(
        _ bridge: OmnixVoiceBridge,
        callStateChanged call: OmnixVoiceBridgeCallInfo
    ) {
        owner?.emitCallState(OmnixVoice.mapCallInfo(call))
    }

    func omnixVoiceBridge(
        _ bridge: OmnixVoiceBridge,
        error code: OmnixBridgeErrorCode,
        detail: String?
    ) {
        owner?.emitError(code: OmnixErrorCode.fromNative(Int(code.rawValue)), detail: detail)
    }
}
