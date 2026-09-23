package com.omnix.voice

import com.omnix.voice.internal.OmnixPermissions
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * SDK-033: RECORD_AUDIO gate surfaces [OmnixErrorCode.PERMISSION_DENIED].
 */
class OmnixPermissionsTest {
    @Test
    fun requireRecordAudio_denied_throwsPermissionDenied() {
        try {
            OmnixPermissions.requireRecordAudioGranted(false)
            fail("expected OmnixVoiceException")
        } catch (e: OmnixVoiceException) {
            assertEquals(OmnixErrorCode.PERMISSION_DENIED, e.code)
            assertEquals(OmnixPermissions.RECORD_AUDIO_DETAIL, e.detail)
            assertTrue(e.message!!.contains("PERMISSION_DENIED"))
        }
    }

    @Test
    fun requireRecordAudio_granted_doesNotThrow() {
        OmnixPermissions.requireRecordAudioGranted(true)
    }
}
