package com.omnix.voice

/**
 * Snapshot of an active / recent call (Issue #1 §20A). No credentials.
 */
data class OmnixCallInfo(
    val callId: String,
    val peerUri: String,
    val peerDisplayName: String,
    val state: OmnixCallState,
    val isOutgoing: Boolean,
    val isMuted: Boolean,
    val isOnHold: Boolean,
)
