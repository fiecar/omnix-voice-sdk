package com.omnix.voice

/**
 * Public event listener (Issue #1 §20A.5). No payload may contain credentials.
 */
interface OmnixVoiceListener {
    fun onRegistrationStateChanged(
        state: OmnixRegistrationState,
        sipCode: Int?,
        reason: String?,
    ) {
    }

    fun onIncomingCall(call: OmnixCallInfo) {}

    fun onCallStateChanged(call: OmnixCallInfo) {}

    fun onAudioRouteChanged(route: OmnixAudioRoute) {}

    fun onError(code: OmnixErrorCode, detail: String?, callId: String?) {}
}
