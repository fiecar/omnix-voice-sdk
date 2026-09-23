package com.omnix.voice.internal

/**
 * Internal JNI declarations for libomnixvoice.so (SDK-031).
 * Public Kotlin facade: [com.omnix.voice.OmnixVoice] (no `external`).
 *
 * Placeholders only; no secrets.
 */
internal object OmnixNative {
    init {
        System.loadLibrary("omnixvoice")
    }

    @JvmStatic
    external fun nativeInit(
        sipServer: String?,
        sipUser: String?,
        authUser: String?,
        sipPassword: String?,
        displayName: String?,
        stunServer: String?,
        verifyCert: Boolean,
        enableSrtp: Boolean,
        codecs: String?,
    ): Int

    @JvmStatic
    external fun nativeShutdown()

    @JvmStatic
    external fun nativeRegister(): Int

    @JvmStatic
    external fun nativeUnregister()

    @JvmStatic
    external fun nativeMakeCall(destination: String): String?

    @JvmStatic
    external fun nativeAnswerCall(callId: String): Int

    @JvmStatic
    external fun nativeRejectCall(callId: String): Int

    @JvmStatic
    external fun nativeHangupCall(callId: String): Int

    @JvmStatic
    external fun nativeHoldCall(callId: String): Int

    @JvmStatic
    external fun nativeResumeCall(callId: String): Int

    @JvmStatic
    external fun nativeSetMuted(callId: String, mute: Boolean): Int

    @JvmStatic
    external fun nativeSetSpeaker(enable: Boolean): Int

    @JvmStatic
    external fun nativeSendDTMF(callId: String, digit: Char): Int

    @JvmStatic
    external fun nativeSetCallback(callback: OmnixNativeCallback?)
}

/**
 * JNI callback target. Int states/codes map to C enums; SDK-032 maps to Kotlin enums.
 */
internal interface OmnixNativeCallback {
    fun onRegistrationStateChanged(state: Int, sipCode: Int, reason: String?)
    fun onCallEvent(
        state: Int,
        callId: String?,
        peerUri: String?,
        peerDisplayName: String?,
        isOutgoing: Boolean,
        isMuted: Boolean,
        isOnHold: Boolean,
    )
    fun onError(code: Int, detail: String?)
}
