// Omnix Voice — registration / call / route enums (Issue #1 §20A). SDK-041.

import Foundation

public enum OmnixRegistrationState: String, Sendable {
    case UNINITIALIZED
    case UNREGISTERED
    case REGISTERING
    case REGISTERED
    case REGISTRATION_FAILED
}

public enum OmnixCallState: String, Sendable {
    case IDLE
    case OUTGOING
    case INCOMING
    case RINGING
    case EARLY_MEDIA
    case CONNECTED
    case HELD
    case ENDING
    case ENDED
    case FAILED
}

public enum OmnixAudioRoute: String, Sendable {
    case EARPIECE
    case SPEAKER
    case WIRED_HEADSET
    case BLUETOOTH
    case UNKNOWN
}

public struct OmnixCallInfo: Sendable {
    public let callId: String
    public let peerUri: String
    public let peerDisplayName: String
    public let state: OmnixCallState
    public let isOutgoing: Bool
    public let isMuted: Bool
    public let isOnHold: Bool

    public init(
        callId: String,
        peerUri: String,
        peerDisplayName: String,
        state: OmnixCallState,
        isOutgoing: Bool,
        isMuted: Bool,
        isOnHold: Bool
    ) {
        self.callId = callId
        self.peerUri = peerUri
        self.peerDisplayName = peerDisplayName
        self.state = state
        self.isOutgoing = isOutgoing
        self.isMuted = isMuted
        self.isOnHold = isOnHold
    }
}

extension OmnixRegistrationState {
    static func fromBridge(_ raw: Int) -> OmnixRegistrationState {
        switch raw {
        case 0: return .UNINITIALIZED
        case 1: return .UNREGISTERED
        case 2: return .REGISTERING
        case 3: return .REGISTERED
        case 4: return .REGISTRATION_FAILED
        default: return .REGISTRATION_FAILED
        }
    }
}

extension OmnixCallState {
    static func fromBridge(_ raw: Int) -> OmnixCallState {
        switch raw {
        case 0: return .IDLE
        case 1: return .OUTGOING
        case 2: return .INCOMING
        case 3: return .RINGING
        case 4: return .EARLY_MEDIA
        case 5: return .CONNECTED
        case 6: return .HELD
        case 7: return .ENDING
        case 8: return .ENDED
        case 9: return .FAILED
        default: return .FAILED
        }
    }
}
