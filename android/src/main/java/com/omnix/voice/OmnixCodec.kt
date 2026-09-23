package com.omnix.voice

/**
 * Codec preference entries (Issue #1 §20A.2). Wire names match C facade.
 */
enum class OmnixCodec(val wireName: String) {
    OPUS("opus"),
    PCMU("pcmu"),
    PCMA("pcma"),
    ;
}
