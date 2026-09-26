package com.omnix.voice

import android.Manifest
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.PackageManager
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith

/**
 * SDK-054: instrumented checks that do not need a SIP server.
 * Real registration remains NOT AVAILABLE (H-3).
 */
@RunWith(AndroidJUnit4::class)
class OmnixVoiceTest {
    @After
    fun tearDown() {
        runCatching { OmnixVoice.shutdown() }
    }

    @Test
    fun initializeWithoutRecordAudioIsPermissionDenied() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val denied =
            object : ContextWrapper(instrumentation.targetContext) {
                override fun checkSelfPermission(permission: String): Int {
                    if (permission == Manifest.permission.RECORD_AUDIO) {
                        return PackageManager.PERMISSION_DENIED
                    }
                    return super.checkSelfPermission(permission)
                }

                override fun checkPermission(
                    permission: String,
                    pid: Int,
                    uid: Int,
                ): Int {
                    if (permission == Manifest.permission.RECORD_AUDIO) {
                        return PackageManager.PERMISSION_DENIED
                    }
                    return super.checkPermission(permission, pid, uid)
                }
            }
        val secret = "placeholder-password"
        val config =
            OmnixVoiceConfig(
                sipServer = "sip.example.com",
                sipUser = "user@example.com",
                sipPassword = secret,
                verifyCert = true,
                enableSrtp = true,
            )
        try {
            OmnixVoice.initialize(denied, config)
            fail("initialize without RECORD_AUDIO should throw")
        } catch (error: OmnixVoiceException) {
            assertEquals(OmnixErrorCode.PERMISSION_DENIED, error.code)
            val text = (error.detail ?: "") + (error.message ?: "")
            assertFalse(text.contains(secret))
        }
    }

    @Test
    fun publicApiHasNoJniTypes() {
        val types =
            listOf(
                OmnixVoice::class.java,
                OmnixVoiceConfig::class.java,
                OmnixCallInfo::class.java,
                OmnixVoiceException::class.java,
            )
        val forbidden = listOf("JNIEnv", "jobject", "jstring", "jclass", "jlong", "JavaVM")
        for (type in types) {
            val signatures =
                type.methods.map { it.toGenericString() } +
                    type.declaredFields.map { it.toGenericString() }
            for (signature in signatures) {
                for (token in forbidden) {
                    assertFalse(
                        "JNI type $token in ${type.simpleName}: $signature",
                        signature.contains(token),
                    )
                }
            }
        }
    }

    @Test
    fun errorCodesMatchFrozenSet() {
        val expected =
            setOf(
                "INITIALIZATION_ERROR",
                "INVALID_CONFIGURATION",
                "REGISTRATION_FAILED",
                "AUTHENTICATION_FAILED",
                "NETWORK_UNAVAILABLE",
                "TLS_ERROR",
                "MEDIA_ERROR",
                "CALL_FAILED",
                "CALL_BUSY",
                "CALL_REJECTED",
                "TIMEOUT",
                "NOT_REGISTERED",
                "INVALID_CALL_STATE",
                "PERMISSION_DENIED",
                "TRANSFER_FAILED",
                "NOT_SUPPORTED",
                "INTERNAL_NATIVE_ERROR",
            )
        val actual = OmnixErrorCode.entries.map { it.name }.toSet()
        assertEquals(expected, actual)
        assertTrue(OmnixErrorCode.entries.distinct().size == expected.size)
    }
}
