// Omnix Voice — config model (Issue #1 §20A.2). SDK-041.
// description / debugDescription MUST redact sipPassword.

import Foundation

public enum OmnixCodec: String, Sendable {
    case opus
    case pcmu
    case pcma

    public var wireName: String { rawValue }
}

public struct OmnixVoiceConfig: Sendable {
    public var sipServer: String
    public var sipUser: String
    public var sipPassword: String
    public var authUser: String?
    public var displayName: String?
    public var stunServer: String?
    public var verifyCert: Bool
    public var enableSrtp: Bool
    public var codecs: [OmnixCodec]

    public init(
        sipServer: String,
        sipUser: String,
        sipPassword: String,
        authUser: String? = nil,
        displayName: String? = nil,
        stunServer: String? = nil,
        verifyCert: Bool = true,
        enableSrtp: Bool = true,
        codecs: [OmnixCodec] = [.opus, .pcmu, .pcma]
    ) {
        self.sipServer = sipServer
        self.sipUser = sipUser
        self.sipPassword = sipPassword
        self.authUser = authUser
        self.displayName = displayName
        self.stunServer = stunServer
        self.verifyCert = verifyCert
        self.enableSrtp = enableSrtp
        self.codecs = codecs
    }
}

extension OmnixVoiceConfig: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        redactedDescription
    }

    public var debugDescription: String {
        redactedDescription
    }

    private var redactedDescription: String {
        "OmnixVoiceConfig(" +
            "sipServer=\(sipServer), " +
            "sipUser=\(sipUser), " +
            "authUser=\(authUser ?? "nil"), " +
            "sipPassword=[REDACTED], " +
            "displayName=\(displayName ?? "nil"), " +
            "stunServer=\(stunServer ?? "nil"), " +
            "verifyCert=\(verifyCert), " +
            "enableSrtp=\(enableSrtp), " +
            "codecs=\(codecs.map(\.wireName))" +
            ")"
    }
}
