package com.omnix.voice

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * SDK-032: [OmnixVoiceConfig.toString] must redact sipPassword.
 */
class OmnixVoiceConfigTest {
    @Test
    fun toString_redactsPassword() {
        val secret = "super-secret-password-do-not-leak"
        val config =
            OmnixVoiceConfig(
                sipServer = "sip.example.com",
                sipUser = "user@example.com",
                sipPassword = secret,
                authUser = "auth@example.com",
            )
        val text = config.toString()
        assertFalse("password must not appear in toString()", text.contains(secret))
        assertTrue("must contain [REDACTED]", text.contains("[REDACTED]"))
        assertTrue(text.contains("sip.example.com"))
        assertTrue(text.contains("user@example.com"))
    }

    @Test
    fun transferCall_stubThrowsNotSupported() {
        var threw = false
        try {
            OmnixVoice.transferCall("call-1", "sip:dest@example.com")
        } catch (e: OmnixVoiceException) {
            threw = true
            assertTrue(e.code == OmnixErrorCode.NOT_SUPPORTED)
        }
        assertTrue(threw)
    }
}
