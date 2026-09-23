package com.omnix.voice.internal

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import com.omnix.voice.OmnixErrorCode
import com.omnix.voice.OmnixVoiceException

/**
 * Android runtime permission helpers (SDK-033).
 *
 * The host app must request [Manifest.permission.RECORD_AUDIO] before
 * [com.omnix.voice.OmnixVoice.initialize]. The SDK only checks; it does not
 * show a system permission dialog.
 */
internal object OmnixPermissions {
    const val RECORD_AUDIO_DETAIL = "RECORD_AUDIO not granted"

    fun isRecordAudioGranted(context: Context): Boolean =
        context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED

    /**
     * Throw [OmnixErrorCode.PERMISSION_DENIED] when [granted] is false.
     * Separated for JVM unit tests without a live [Context].
     */
    fun requireRecordAudioGranted(granted: Boolean) {
        if (!granted) {
            throw OmnixVoiceException(
                OmnixErrorCode.PERMISSION_DENIED,
                RECORD_AUDIO_DETAIL,
            )
        }
    }
}
