// Omnix Voice — public Swift facade (Issue #1 §20A.1).
// SDK-041: wraps OmnixVoiceBridge. SDK-042: AVAudioSession via OmnixAudioSession.
// Public API exposes no ObjC / Baresip / re types.
// Placeholders only; never log sipPassword.

import Foundation

public final class OmnixVoice {
    public static let shared = OmnixVoice()

    public weak var delegate: OmnixVoiceDelegate?

    private let lock = NSLock()
    private var audioRoute: OmnixAudioRoute = .UNKNOWN
    private let bridgeSink: BridgeSink
    private let audioSession: OmnixAudioSession
    private var trackedCalls: [String: OmnixCallState] = [:]

    private init() {
        bridgeSink = BridgeSink()
        bridgeSink.owner = self
        audioSession = OmnixAudioSession()
        audioSession.onRouteChanged = { [weak self] route in
            self?.handleExternalRouteChange(route)
        }
        // ObjC `sharedBridge` imports as `shared` in Swift.
        OmnixVoiceBridge.shared.delegate = bridgeSink
    }

    public var registrationState: OmnixRegistrationState {
        lock.lock()
        defer { lock.unlock() }
        let raw = Int(OmnixVoiceBridge.shared.registrationState.rawValue)
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

        do {
            try OmnixVoiceBridge.shared.initialize(with: bridgeConfig)
        } catch {
            throw mapThrown(error)
        }
    }

    public func shutdown() {
        lock.lock()
        defer { lock.unlock() }
        try? audioSession.endCallAudio()
        OmnixVoiceBridge.shared.shutdown()
        trackedCalls.removeAll()
        audioRoute = .UNKNOWN
    }

    public func register() throws {
        lock.lock()
        defer { lock.unlock() }
        do {
            try OmnixVoiceBridge.shared.register()
        } catch {
            throw mapThrown(error)
        }
    }

    public func unregister() {
        lock.lock()
        defer { lock.unlock() }
        OmnixVoiceBridge.shared.unregister()
    }

    public func makeCall(destination: String) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        var callId: NSString?
        do {
            try OmnixVoiceBridge.shared.makeCall(destination, callId: &callId)
        } catch {
            throw mapThrown(error)
        }
        guard let id = callId as String?, !id.isEmpty else {
            throw OmnixVoiceError(code: .CALL_FAILED, detail: "makeCall failed")
        }
        return id
    }

    public func answerCall(callId: String) throws {
        try invokeCall(callId) { try $0.answerCall($1) }
    }

    public func rejectCall(callId: String) throws {
        try invokeCall(callId) { try $0.rejectCall($1) }
    }

    public func hangupCall(callId: String) throws {
        try invokeCall(callId) { try $0.hangupCall($1) }
    }

    public func holdCall(callId: String) throws {
        try invokeCall(callId) { try $0.holdCall($1) }
    }

    public func resumeCall(callId: String) throws {
        try invokeCall(callId) { try $0.resumeCall($1) }
    }

    public func setMuted(callId: String, muted: Bool) throws {
        try invokeCall(callId) { try $0.setMuted(muted, callId: $1) }
    }

    public func setSpeakerEnabled(_ enabled: Bool) throws {
        lock.lock()
        defer { lock.unlock() }
        do {
            try OmnixVoiceBridge.shared.setSpeakerEnabled(enabled)
            try audioSession.setSpeakerEnabled(enabled)
        } catch let error as OmnixVoiceError {
            throw error
        } catch {
            // AVAudioSession failures surface as MEDIA_ERROR; bridge NSError mapped.
            if (error as NSError).domain == OmnixVoiceBridgeErrorDomain {
                throw mapThrown(error)
            }
            throw OmnixVoiceError(
                code: .MEDIA_ERROR,
                detail: error.localizedDescription
            )
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
        try invokeCall(callId) { try $0.sendDTMF(value, callId: $1) }
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
        guard let info = OmnixVoiceBridge.shared.callInfo(forCallId: callId) else {
            return nil
        }
        return Self.mapCallInfo(info)
    }

    // MARK: - Internal

    private func invokeCall(
        _ callId: String,
        _ body: (OmnixVoiceBridge, String) throws -> Void
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        if callId.isEmpty {
            throw OmnixVoiceError(
                code: .INVALID_CONFIGURATION,
                detail: "callId is required"
            )
        }
        do {
            try body(OmnixVoiceBridge.shared, callId)
        } catch {
            throw mapThrown(error)
        }
    }

    private func mapThrown(_ error: Error) -> OmnixVoiceError {
        let ns = error as NSError
        let code = OmnixErrorCode.fromNative(ns.code)
        return OmnixVoiceError(code: code, detail: ns.localizedDescription)
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
        rememberCall(call)
        syncCallAudio()
        delegate?.incomingCall(call)
    }

    fileprivate func emitCallState(_ call: OmnixCallInfo) {
        rememberCall(call)
        syncCallAudio()
        delegate?.callStateChanged(call)
    }

    fileprivate func emitError(code: OmnixErrorCode, detail: String?) {
        delegate?.didReceiveError(code, detail: detail, callId: nil)
    }

    private func handleExternalRouteChange(_ route: OmnixAudioRoute) {
        lock.lock()
        audioRoute = route
        lock.unlock()
        delegate?.audioRouteChanged(route)
    }

    /// SDK-042: activate AVAudioSession while any call is non-terminal;
    /// deactivate with notifyOthersOnDeactivation when all calls end.
    private func syncCallAudio() {
        lock.lock()
        let active = trackedCalls.values.contains { Self.isActiveCallState($0) }
        lock.unlock()

        if active {
            do {
                try audioSession.startCallAudio()
            } catch {
                emitError(code: .MEDIA_ERROR, detail: error.localizedDescription)
            }
        } else {
            do {
                try audioSession.endCallAudio()
            } catch {
                emitError(code: .MEDIA_ERROR, detail: error.localizedDescription)
            }
        }
    }

    fileprivate func rememberCall(_ call: OmnixCallInfo) {
        lock.lock()
        trackedCalls[call.callId] = call.state
        lock.unlock()
    }

    private static func isActiveCallState(_ state: OmnixCallState) -> Bool {
        switch state {
        case .OUTGOING, .INCOMING, .RINGING, .EARLY_MEDIA, .CONNECTED, .HELD, .ENDING:
            return true
        case .IDLE, .ENDED, .FAILED:
            return false
        }
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
