package com.omnix.voice

/**
 * Call states (Issue #1 §20A.4). Names are canonical and frozen.
 */
enum class OmnixCallState {
    IDLE,
    OUTGOING,
    INCOMING,
    RINGING,
    EARLY_MEDIA,
    CONNECTED,
    HELD,
    ENDING,
    ENDED,
    FAILED,
    ;

    internal companion object {
        fun fromNative(code: Int): OmnixCallState =
            when (code) {
                0 -> IDLE
                1 -> OUTGOING
                2 -> INCOMING
                3 -> RINGING
                4 -> EARLY_MEDIA
                5 -> CONNECTED
                6 -> HELD
                7 -> ENDING
                8 -> ENDED
                9 -> FAILED
                else -> FAILED
            }
    }
}
