package com.omnix.voice

import android.content.Context
import android.util.Log
import com.omnix.voice.internal.OmnixEventDispatcher
import com.omnix.voice.internal.OmnixNative
import com.omnix.voice.internal.OmnixNativeCallback
import com.omnix.voice.internal.OmnixPermissions
import java.util.concurrent.ConcurrentHashMap

/**
 * Public Omnix Voice singleton (Issue #1 §20A.1 / SDK-032).
 *
 * No `external` / JNI types. Baresip/re types must never appear here.
 * Password is passed to native once and is never persisted by this SDK.
 * [initialize] requires [android.Manifest.permission.RECORD_AUDIO] (SDK-033).
 */
object OmnixVoice {
    private const val TAG = "OmnixVoice"
    private const val NATIVE_OK = 0

    private val lock = Any()
    private val dispatcher = OmnixEventDispatcher()
    private val calls = ConcurrentHashMap<String, OmnixCallInfo>()

    @Volatile
    private var appContext: Context? = null

    @Volatile
    private var initialized: Boolean = false

    @Volatile
    private var audioRoute: OmnixAudioRoute = OmnixAudioRoute.UNKNOWN

    @Volatile
    var registrationState: OmnixRegistrationState =
        OmnixRegistrationState.UNINITIALIZED
        private set

    private val nativeCallback =
        object : OmnixNativeCallback {
            override fun onRegistrationStateChanged(
                state: Int,
                sipCode: Int,
                reason: String?,
            ) {
                val mapped = OmnixRegistrationState.fromNative(state)
                registrationState = mapped
                val codeOrNull = if (sipCode == 0) null else sipCode
                dispatcher.dispatch {
                    it.onRegistrationStateChanged(mapped, codeOrNull, reason)
                }
            }

            override fun onCallEvent(
                state: Int,
                callId: String?,
                peerUri: String?,
                peerDisplayName: String?,
                isOutgoing: Boolean,
                isMuted: Boolean,
                isOnHold: Boolean,
            ) {
                val id = callId ?: return
                val mapped = OmnixCallState.fromNative(state)
                val info =
                    OmnixCallInfo(
                        callId = id,
                        peerUri = peerUri.orEmpty(),
                        peerDisplayName = peerDisplayName.orEmpty(),
                        state = mapped,
                        isOutgoing = isOutgoing,
                        isMuted = isMuted,
                        isOnHold = isOnHold,
                    )
                calls[id] = info
                if (mapped == OmnixCallState.INCOMING) {
                    dispatcher.dispatch { it.onIncomingCall(info) }
                }
                dispatcher.dispatch { it.onCallStateChanged(info) }
                if (mapped == OmnixCallState.ENDED || mapped == OmnixCallState.FAILED) {
                    // Keep last snapshot for getCallInfo briefly; remove idle noise later.
                }
            }

            override fun onError(code: Int, detail: String?) {
                val mapped = OmnixErrorCode.fromNative(code)
                // Never log detail if it could contain secrets; facade detail is opaque.
                Log.w(TAG, "native error code=$mapped")
                dispatcher.dispatch { it.onError(mapped, detail, null) }
            }
        }

    /**
     * Initialize the SDK. Stores [Context.getApplicationContext] only.
     * Does not write [OmnixVoiceConfig.sipPassword] to disk.
     *
     * Requires [android.Manifest.permission.RECORD_AUDIO] already granted.
     * If missing, fires [OmnixVoiceListener.onError] with
     * [OmnixErrorCode.PERMISSION_DENIED] and throws [OmnixVoiceException].
     */
    @JvmStatic
    fun initialize(context: Context, config: OmnixVoiceConfig) {
        synchronized(lock) {
            if (initialized) {
                throw OmnixVoiceException(
                    OmnixErrorCode.INVALID_CALL_STATE,
                    "already initialized",
                )
            }
            if (config.sipServer.isBlank() || config.sipUser.isBlank()) {
                throw OmnixVoiceException(
                    OmnixErrorCode.INVALID_CONFIGURATION,
                    "sipServer and sipUser are required",
                )
            }

            // SDK-033: check only — host must request the runtime permission.
            if (!OmnixPermissions.isRecordAudioGranted(context)) {
                val detail = OmnixPermissions.RECORD_AUDIO_DETAIL
                dispatcher.dispatch {
                    it.onError(OmnixErrorCode.PERMISSION_DENIED, detail, null)
                }
                OmnixPermissions.requireRecordAudioGranted(false)
            }

            appContext = context.applicationContext
            OmnixNative.nativeSetCallback(nativeCallback)

            val codecsCsv =
                config.codecs.joinToString(",") { it.wireName }.ifBlank {
                    "opus,pcmu,pcma"
                }

            val rc =
                OmnixNative.nativeInit(
                    sipServer = config.sipServer,
                    sipUser = config.sipUser,
                    authUser = config.authUser,
                    sipPassword = config.sipPassword,
                    displayName = config.displayName,
                    stunServer = config.stunServer,
                    verifyCert = config.verifyCert,
                    enableSrtp = config.enableSrtp,
                    codecs = codecsCsv,
                )
            throwIfError(rc)

            initialized = true
            registrationState = OmnixRegistrationState.UNREGISTERED
            Log.i(TAG, "initialized (password not logged)")
        }
    }

    @JvmStatic
    fun shutdown() {
        synchronized(lock) {
            if (!initialized) {
                return
            }
            OmnixNative.nativeSetCallback(null)
            OmnixNative.nativeShutdown()
            calls.clear()
            dispatcher.clear()
            appContext = null
            audioRoute = OmnixAudioRoute.UNKNOWN
            registrationState = OmnixRegistrationState.UNINITIALIZED
            initialized = false
        }
    }

    @JvmStatic
    fun register() {
        synchronized(lock) {
            ensureInitialized()
            throwIfError(OmnixNative.nativeRegister())
        }
    }

    @JvmStatic
    fun unregister() {
        synchronized(lock) {
            ensureInitialized()
            OmnixNative.nativeUnregister()
        }
    }

    @JvmStatic
    fun makeCall(destination: String): String {
        synchronized(lock) {
            ensureInitialized()
            if (destination.isBlank()) {
                throw OmnixVoiceException(
                    OmnixErrorCode.INVALID_CONFIGURATION,
                    "destination is required",
                )
            }
            val callId =
                OmnixNative.nativeMakeCall(destination)
                    ?: throw OmnixVoiceException(
                        OmnixErrorCode.CALL_FAILED,
                        "makeCall failed",
                    )
            return callId
        }
    }

    @JvmStatic
    fun answerCall(callId: String) {
        synchronized(lock) {
            ensureInitialized()
            throwIfError(OmnixNative.nativeAnswerCall(requireCallId(callId)))
        }
    }

    @JvmStatic
    fun rejectCall(callId: String) {
        synchronized(lock) {
            ensureInitialized()
            throwIfError(OmnixNative.nativeRejectCall(requireCallId(callId)))
        }
    }

    @JvmStatic
    fun hangupCall(callId: String) {
        synchronized(lock) {
            ensureInitialized()
            throwIfError(OmnixNative.nativeHangupCall(requireCallId(callId)))
        }
    }

    @JvmStatic
    fun holdCall(callId: String) {
        synchronized(lock) {
            ensureInitialized()
            throwIfError(OmnixNative.nativeHoldCall(requireCallId(callId)))
        }
    }

    @JvmStatic
    fun resumeCall(callId: String) {
        synchronized(lock) {
            ensureInitialized()
            throwIfError(OmnixNative.nativeResumeCall(requireCallId(callId)))
        }
    }

    @JvmStatic
    fun setMuted(callId: String, muted: Boolean) {
        synchronized(lock) {
            ensureInitialized()
            throwIfError(OmnixNative.nativeSetMuted(requireCallId(callId), muted))
        }
    }

    @JvmStatic
    fun setSpeakerEnabled(enabled: Boolean) {
        synchronized(lock) {
            ensureInitialized()
            throwIfError(OmnixNative.nativeSetSpeaker(enabled))
            audioRoute =
                if (enabled) OmnixAudioRoute.SPEAKER else OmnixAudioRoute.EARPIECE
            val route = audioRoute
            dispatcher.dispatch { it.onAudioRouteChanged(route) }
        }
    }

    @JvmStatic
    fun sendDTMF(callId: String, digit: Char) {
        synchronized(lock) {
            ensureInitialized()
            throwIfError(OmnixNative.nativeSendDTMF(requireCallId(callId), digit))
        }
    }

    /**
     * Blind transfer stub until SDK-024. Always throws [OmnixErrorCode.NOT_SUPPORTED].
     */
    @JvmStatic
    fun transferCall(callId: String, destination: String) {
        requireCallId(callId)
        if (destination.isBlank()) {
            throw OmnixVoiceException(
                OmnixErrorCode.INVALID_CONFIGURATION,
                "destination is required",
            )
        }
        throw OmnixVoiceException(
            OmnixErrorCode.NOT_SUPPORTED,
            "blind transfer requires SDK-024",
        )
    }

    @JvmStatic
    fun getCallInfo(callId: String): OmnixCallInfo? = calls[callId]

    @JvmStatic
    fun addListener(listener: OmnixVoiceListener) {
        dispatcher.addListener(listener)
    }

    @JvmStatic
    fun removeListener(listener: OmnixVoiceListener) {
        dispatcher.removeListener(listener)
    }

    private fun ensureInitialized() {
        if (!initialized) {
            throw OmnixVoiceException(
                OmnixErrorCode.INVALID_CALL_STATE,
                "SDK not initialized",
            )
        }
    }

    private fun requireCallId(callId: String): String {
        if (callId.isBlank()) {
            throw OmnixVoiceException(
                OmnixErrorCode.INVALID_CONFIGURATION,
                "callId is required",
            )
        }
        return callId
    }

    private fun throwIfError(code: Int) {
        if (code == NATIVE_OK) {
            return
        }
        val mapped = OmnixErrorCode.fromNative(code)
        throw OmnixVoiceException(mapped, mapped.name)
    }
}
