package com.omnix.voice

/**
 * Registration states (Issue #1 §20A.3). Names are canonical and frozen.
 */
enum class OmnixRegistrationState {
    UNINITIALIZED,
    UNREGISTERED,
    REGISTERING,
    REGISTERED,
    REGISTRATION_FAILED,
    ;

    internal companion object {
        fun fromNative(code: Int): OmnixRegistrationState =
            when (code) {
                0 -> UNINITIALIZED
                1 -> UNREGISTERED
                2 -> REGISTERING
                3 -> REGISTERED
                4 -> REGISTRATION_FAILED
                else -> REGISTRATION_FAILED
            }
    }
}
