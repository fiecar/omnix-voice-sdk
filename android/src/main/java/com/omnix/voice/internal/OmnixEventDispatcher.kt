package com.omnix.voice.internal

import android.os.Handler
import android.os.Looper
import android.util.Log
import com.omnix.voice.OmnixVoiceListener
import java.util.concurrent.CopyOnWriteArraySet

/**
 * Fans out Omnix events to registered listeners on the main thread (SDK-032).
 * Falls back to inline dispatch when no main looper exists (JVM unit tests).
 */
internal class OmnixEventDispatcher {
    private val listeners = CopyOnWriteArraySet<OmnixVoiceListener>()

    private val mainHandler: Handler? by lazy {
        val looper = Looper.getMainLooper() ?: return@lazy null
        Handler(looper)
    }

    fun addListener(listener: OmnixVoiceListener) {
        listeners.add(listener)
    }

    fun removeListener(listener: OmnixVoiceListener) {
        listeners.remove(listener)
    }

    fun clear() {
        listeners.clear()
    }

    fun dispatch(block: (OmnixVoiceListener) -> Unit) {
        val run = Runnable {
            for (listener in listeners) {
                try {
                    block(listener)
                } catch (t: Throwable) {
                    Log.e(TAG, "listener threw", t)
                }
            }
        }
        val handler = mainHandler
        val main = Looper.getMainLooper()
        if (handler == null || main == null || Looper.myLooper() == main) {
            run.run()
        } else {
            handler.post(run)
        }
    }

    companion object {
        private const val TAG = "OmnixVoice"
    }
}
