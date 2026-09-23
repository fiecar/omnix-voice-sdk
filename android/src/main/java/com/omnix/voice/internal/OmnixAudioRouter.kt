package com.omnix.voice.internal

import android.content.Context
import android.media.AudioManager

/**
 * Android audio focus + routing for VoIP calls (SDK-034 / Issue #2).
 *
 * At call start:
 * - Request [AudioManager.AUDIOFOCUS_GAIN_TRANSIENT] with
 *   [android.media.AudioAttributes.USAGE_VOICE_COMMUNICATION]
 * - Set [AudioManager.MODE_IN_COMMUNICATION]
 * - Apply speaker preference via [AudioManager.setSpeakerphoneOn]
 *
 * At call end:
 * - Release audio focus
 * - Clear speakerphone
 * - Restore previous audio mode
 *
 * Platform applies the C-facade speaker preference from SDK-021.
 * No [android.util.Log] here so JVM unit tests run without Robolectric.
 */
internal class OmnixAudioRouter(
    private val audio: OmnixAudioManagerBridge,
) {
    @Volatile
    private var sessionActive: Boolean = false

    @Volatile
    private var previousMode: Int = AudioManager.MODE_NORMAL

    @Volatile
    private var speakerEnabled: Boolean = false

    @Volatile
    private var focusHeld: Boolean = false

    val isSessionActive: Boolean
        get() = sessionActive

    val isFocusHeld: Boolean
        get() = focusHeld

    val isSpeakerEnabled: Boolean
        get() = speakerEnabled

    /**
     * Begin call audio: focus + MODE_IN_COMMUNICATION + speaker preference.
     * Idempotent while a session is already active.
     */
    fun startCallAudio() {
        if (sessionActive) {
            applySpeaker()
            return
        }
        previousMode = audio.mode
        audio.mode = AudioManager.MODE_IN_COMMUNICATION
        focusHeld = audio.requestVoiceCommunicationFocus()
        sessionActive = true
        applySpeaker()
    }

    /**
     * End call audio: abandon focus, clear speaker, restore prior mode.
     * Idempotent when no session is active.
     */
    fun endCallAudio() {
        if (!sessionActive) {
            return
        }
        audio.setSpeakerphoneOn(false)
        audio.abandonFocus()
        focusHeld = false
        audio.mode = previousMode
        sessionActive = false
    }

    /**
     * Update speakerphone preference. Applied immediately when a call session
     * is active; otherwise stored for the next [startCallAudio].
     */
    fun setSpeakerEnabled(enabled: Boolean) {
        speakerEnabled = enabled
        if (sessionActive) {
            applySpeaker()
        }
    }

    private fun applySpeaker() {
        audio.setSpeakerphoneOn(speakerEnabled)
    }

    companion object {
        fun from(context: Context): OmnixAudioRouter =
            OmnixAudioRouter(SystemOmnixAudioManagerBridge.from(context))
    }
}
