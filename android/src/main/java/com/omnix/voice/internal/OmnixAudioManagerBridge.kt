package com.omnix.voice.internal

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.util.Log

/**
 * Thin bridge over [AudioManager] so [OmnixAudioRouter] can be unit-tested
 * with a fake (no Robolectric / Mockito dependency for SDK-034).
 *
 * Interface stays free of [AudioFocusRequest] so JVM tests need no Android stubs
 * beyond what AGP already provides for the production class.
 *
 * minSdk 26 → [AudioFocusRequest] / [AudioAttributes] APIs are available.
 */
internal interface OmnixAudioManagerBridge {
    var mode: Int

    /** Request [AudioManager.AUDIOFOCUS_GAIN_TRANSIENT] for voice communication. */
    fun requestVoiceCommunicationFocus(): Boolean

    fun abandonFocus()

    fun setSpeakerphoneOn(on: Boolean)

    fun isSpeakerphoneOn(): Boolean
}

internal class SystemOmnixAudioManagerBridge(
    private val audioManager: AudioManager,
) : OmnixAudioManagerBridge {
    private var focusRequest: AudioFocusRequest? = null

    private val focusListener =
        AudioManager.OnAudioFocusChangeListener { change ->
            // MVP: log only. Duck/pause policy is Phase 2.
            Log.i(TAG, "audio focus change=$change")
        }

    override var mode: Int
        get() = audioManager.mode
        set(value) {
            audioManager.mode = value
        }

    override fun requestVoiceCommunicationFocus(): Boolean {
        abandonFocus()
        val attrs =
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
        val request =
            AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                .setAudioAttributes(attrs)
                .setOnAudioFocusChangeListener(focusListener)
                .setAcceptsDelayedFocusGain(false)
                .build()
        val result = audioManager.requestAudioFocus(request)
        if (result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
            focusRequest = request
            return true
        }
        Log.w(TAG, "audio focus not granted result=$result")
        return false
    }

    override fun abandonFocus() {
        val req = focusRequest ?: return
        audioManager.abandonAudioFocusRequest(req)
        focusRequest = null
    }

    override fun setSpeakerphoneOn(on: Boolean) {
        @Suppress("DEPRECATION")
        audioManager.isSpeakerphoneOn = on
    }

    override fun isSpeakerphoneOn(): Boolean {
        @Suppress("DEPRECATION")
        return audioManager.isSpeakerphoneOn
    }

    companion object {
        private const val TAG = "OmnixAudioRouter"

        fun from(context: Context): SystemOmnixAudioManagerBridge {
            val am =
                context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            return SystemOmnixAudioManagerBridge(am)
        }
    }
}
