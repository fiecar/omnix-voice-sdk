package com.omnix.voice

import android.Manifest
import android.system.Os
import android.system.OsConstants
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.rule.GrantPermissionRule
import org.junit.Assert.assertEquals
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * SDK-038 — runtime gate for 16 KB page-size devices/emulators.
 *
 * On 4 KB devices this test **skips** (manual release gate still requires a
 * 16 KB image where `getconf PAGE_SIZE` / `Os.sysconf(_SC_PAGESIZE)` = 16384).
 * Do not set `android:pageSizeCompat` on demo/test apps to mask failures.
 */
@RunWith(AndroidJUnit4::class)
class Omnix16KbPageTest {
    @get:Rule
    val recordAudioPermission: GrantPermissionRule =
        GrantPermissionRule.grant(Manifest.permission.RECORD_AUDIO)

    @Test
    fun loadInitializeShutdownOn16KbPages() {
        val pageSize = Os.sysconf(OsConstants._SC_PAGESIZE)
        assumeTrue(
            "SKIP: requires 16 KB page device/emulator (got PAGE_SIZE=$pageSize; " +
                "adb shell getconf PAGE_SIZE must be 16384). Manual release gate.",
            pageSize == 16384L,
        )

        assertEquals(16384L, pageSize)

        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val config =
            OmnixVoiceConfig(
                sipServer = "sip.example.com",
                sipUser = "user@example.com",
                sipPassword = "placeholder-password",
                displayName = "SDK-038-16kb",
                verifyCert = true,
                enableSrtp = true,
            )

        try {
            OmnixVoice.initialize(context, config)
            OmnixVoice.shutdown()
        } finally {
            // Idempotent if initialize failed mid-way.
            runCatching { OmnixVoice.shutdown() }
        }
    }
}
