// Omnix Voice — public error codes (Issue #1 §20A.6). SDK-041.
// No Baresip/re types. OMNIX_ERR_OK never surfaces here.

import Foundation

public enum OmnixErrorCode: String, Sendable {
    case INITIALIZATION_ERROR
    case INVALID_CONFIGURATION
    case REGISTRATION_FAILED
    case AUTHENTICATION_FAILED
    case NETWORK_UNAVAILABLE
    case TLS_ERROR
    case MEDIA_ERROR
    case CALL_FAILED
    case CALL_BUSY
    case CALL_REJECTED
    case TIMEOUT
    case NOT_REGISTERED
    case INVALID_CALL_STATE
    case PERMISSION_DENIED
    case TRANSFER_FAILED
    case NOT_SUPPORTED
    case INTERNAL_NATIVE_ERROR
}

/// Synchronous API failure (Issue #1 §20A.1). Async failures also arrive via
/// `OmnixVoiceDelegate.didReceiveError`.
public struct OmnixVoiceError: Error, Sendable {
    public let code: OmnixErrorCode
    public let detail: String?

    public init(code: OmnixErrorCode, detail: String? = nil) {
        self.code = code
        self.detail = detail
    }
}

extension OmnixErrorCode {
    /// Map `omnix_error_t` / bridge ordinal (non-zero) to Swift code.
    static func fromNative(_ code: Int) -> OmnixErrorCode {
        switch code {
        case 1: return .INITIALIZATION_ERROR
        case 2: return .INVALID_CONFIGURATION
        case 3: return .REGISTRATION_FAILED
        case 4: return .AUTHENTICATION_FAILED
        case 5: return .NETWORK_UNAVAILABLE
        case 6: return .TLS_ERROR
        case 7: return .MEDIA_ERROR
        case 8: return .CALL_FAILED
        case 9: return .CALL_BUSY
        case 10: return .CALL_REJECTED
        case 11: return .TIMEOUT
        case 12: return .NOT_REGISTERED
        case 13: return .INVALID_CALL_STATE
        case 14: return .PERMISSION_DENIED
        case 15: return .TRANSFER_FAILED
        case 16: return .NOT_SUPPORTED
        case 17: return .INTERNAL_NATIVE_ERROR
        default: return .INTERNAL_NATIVE_ERROR
        }
    }
}
