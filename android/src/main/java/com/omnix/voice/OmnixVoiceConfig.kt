package com.omnix.voice

/**
 * SDK configuration (Issue #1 §20A.2).
 *
 * [sipPassword] must never be logged, persisted, or echoed in events.
 * [toString] always redacts it as `[REDACTED]`.
 */
data class OmnixVoiceConfig(
    val sipServer: String,
    val sipUser: String,
    val sipPassword: String,
    val authUser: String? = null,
    val displayName: String? = null,
    val stunServer: String? = null,
    val verifyCert: Boolean = true,
    val enableSrtp: Boolean = true,
    val codecs: List<OmnixCodec> =
        listOf(OmnixCodec.OPUS, OmnixCodec.PCMU, OmnixCodec.PCMA),
) {
    override fun toString(): String =
        "OmnixVoiceConfig(" +
            "sipServer=$sipServer, " +
            "sipUser=$sipUser, " +
            "authUser=$authUser, " +
            "sipPassword=[REDACTED], " +
            "displayName=$displayName, " +
            "stunServer=$stunServer, " +
            "verifyCert=$verifyCert, " +
            "enableSrtp=$enableSrtp, " +
            "codecs=$codecs)"
}
