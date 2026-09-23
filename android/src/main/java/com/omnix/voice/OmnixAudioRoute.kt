package com.omnix.voice

/**
 * Audio output route (Issue #1 §20A / §19). Full device routing = SDK-034.
 */
enum class OmnixAudioRoute {
    EARPIECE,
    SPEAKER,
    WIRED_HEADSET,
    BLUETOOTH,
    UNKNOWN,
}
