package com.omnix.voice

import com.omnix.voice.internal.OmnixAudioManagerBridge
import com.omnix.voice.internal.OmnixAudioRouter
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * SDK-034: audio focus, MODE_IN_COMMUNICATION, speaker routing, release on end.
 * Uses a fake [OmnixAudioManagerBridge] (no device / Robolectric).
 */
class OmnixAudioRouterTest {
    @Test
    fun startCallAudio_requestsFocus_setsModeInCommunication() {
        val fake = FakeAudioBridge(initialMode = MODE_NORMAL)
        val router = OmnixAudioRouter(fake)

        router.startCallAudio()

        assertTrue(router.isSessionActive)
        assertTrue(router.isFocusHeld)
        assertEquals(1, fake.focusRequestCount)
        assertEquals(MODE_IN_COMMUNICATION, fake.mode)
    }

    @Test
    fun setSpeakerEnabled_duringSession_callsSetSpeakerphoneOn() {
        val fake = FakeAudioBridge()
        val router = OmnixAudioRouter(fake)
        router.startCallAudio()
        val before = fake.speakerSetCount

        router.setSpeakerEnabled(true)

        assertTrue(router.isSpeakerEnabled)
        assertTrue(fake.speakerphoneOn)
        assertTrue(fake.speakerSetCount > before)
    }

    @Test
    fun setSpeakerEnabled_beforeSession_deferredUntilStart() {
        val fake = FakeAudioBridge()
        val router = OmnixAudioRouter(fake)

        router.setSpeakerEnabled(true)
        assertFalse(fake.speakerphoneOn)
        assertEquals(0, fake.speakerSetCount)

        router.startCallAudio()
        assertTrue(fake.speakerphoneOn)
    }

    @Test
    fun endCallAudio_abandonsFocus_clearsSpeaker_restoresMode() {
        val fake = FakeAudioBridge(initialMode = MODE_RINGTONE)
        val router = OmnixAudioRouter(fake)
        router.startCallAudio()
        router.setSpeakerEnabled(true)

        router.endCallAudio()

        assertFalse(router.isSessionActive)
        assertFalse(router.isFocusHeld)
        assertEquals(1, fake.focusAbandonCount)
        assertFalse(fake.speakerphoneOn)
        assertEquals(MODE_RINGTONE, fake.mode)
    }

    @Test
    fun startCallAudio_idempotent_doesNotDoubleRequestFocus() {
        val fake = FakeAudioBridge()
        val router = OmnixAudioRouter(fake)

        router.startCallAudio()
        router.startCallAudio()

        assertEquals(1, fake.focusRequestCount)
        assertTrue(router.isSessionActive)
    }

    @Test
    fun endCallAudio_whenIdle_isNoOp() {
        val fake = FakeAudioBridge(initialMode = MODE_NORMAL)
        val router = OmnixAudioRouter(fake)

        router.endCallAudio()

        assertEquals(0, fake.focusAbandonCount)
        assertEquals(MODE_NORMAL, fake.mode)
    }

    private class FakeAudioBridge(
        initialMode: Int = MODE_NORMAL,
        private val grantFocus: Boolean = true,
    ) : OmnixAudioManagerBridge {
        override var mode: Int = initialMode
        var speakerphoneOn: Boolean = false
            private set
        var focusRequestCount: Int = 0
            private set
        var focusAbandonCount: Int = 0
            private set
        var speakerSetCount: Int = 0
            private set
        private var focusHeld: Boolean = false

        override fun requestVoiceCommunicationFocus(): Boolean {
            focusRequestCount++
            focusHeld = grantFocus
            return grantFocus
        }

        override fun abandonFocus() {
            if (focusHeld) {
                focusAbandonCount++
                focusHeld = false
            }
        }

        override fun setSpeakerphoneOn(on: Boolean) {
            speakerSetCount++
            speakerphoneOn = on
        }

        override fun isSpeakerphoneOn(): Boolean = speakerphoneOn
    }

    companion object {
        // Mirror android.media.AudioManager constants (minSdk 26).
        private const val MODE_NORMAL = 0
        private const val MODE_RINGTONE = 1
        private const val MODE_IN_COMMUNICATION = 3
    }
}
