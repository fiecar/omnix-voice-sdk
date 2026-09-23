package com.omnix.voice

/**
 * Canonical error codes (Issue #1 §20A.6). `OMNIX_ERR_OK` never surfaces here.
 */
enum class OmnixErrorCode {
    INITIALIZATION_ERROR,
    INVALID_CONFIGURATION,
    REGISTRATION_FAILED,
    AUTHENTICATION_FAILED,
    NETWORK_UNAVAILABLE,
    TLS_ERROR,
    MEDIA_ERROR,
    CALL_FAILED,
    CALL_BUSY,
    CALL_REJECTED,
    TIMEOUT,
    NOT_REGISTERED,
    INVALID_CALL_STATE,
    PERMISSION_DENIED,
    TRANSFER_FAILED,
    NOT_SUPPORTED,
    INTERNAL_NATIVE_ERROR,
    ;

    internal companion object {
        /** Map `omnix_error_t` ordinal (non-zero) to Kotlin code. */
        fun fromNative(code: Int): OmnixErrorCode =
            when (code) {
                1 -> INITIALIZATION_ERROR
                2 -> INVALID_CONFIGURATION
                3 -> REGISTRATION_FAILED
                4 -> AUTHENTICATION_FAILED
                5 -> NETWORK_UNAVAILABLE
                6 -> TLS_ERROR
                7 -> MEDIA_ERROR
                8 -> CALL_FAILED
                9 -> CALL_BUSY
                10 -> CALL_REJECTED
                11 -> TIMEOUT
                12 -> NOT_REGISTERED
                13 -> INVALID_CALL_STATE
                14 -> PERMISSION_DENIED
                15 -> TRANSFER_FAILED
                16 -> NOT_SUPPORTED
                17 -> INTERNAL_NATIVE_ERROR
                else -> INTERNAL_NATIVE_ERROR
            }
    }
}

/**
 * Synchronous API failure (Issue #1 §20A.1). Async failures also arrive via
 * [OmnixVoiceListener.onError].
 */
class OmnixVoiceException(
    val code: OmnixErrorCode,
    val detail: String? = null,
) : Exception(buildMessage(code, detail)) {
    companion object {
        private fun buildMessage(code: OmnixErrorCode, detail: String?): String =
            if (detail.isNullOrBlank()) {
                "OmnixVoice error: $code"
            } else {
                "OmnixVoice error: $code — $detail"
            }
    }
}
