package com.omnix.voice.rn

import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.bridge.WritableMap
import com.facebook.react.module.annotations.ReactModule
import com.facebook.react.modules.core.DeviceEventManagerModule
import com.omnix.voice.OmnixAudioRoute
import com.omnix.voice.OmnixCallInfo
import com.omnix.voice.OmnixCallState
import com.omnix.voice.OmnixCodec
import com.omnix.voice.OmnixErrorCode
import com.omnix.voice.OmnixRegistrationState
import com.omnix.voice.OmnixVoice
import com.omnix.voice.OmnixVoiceConfig
import com.omnix.voice.OmnixVoiceException
import com.omnix.voice.OmnixVoiceListener

/**
 * Android New Architecture bridge (SDK-048).
 *
 * React Native -> this TurboModule -> public Omnix Android SDK.
 * Upstream SIP stack types stay behind that SDK.
 * Credential persistence is the host app's responsibility. This module does
 * not log configuration and does not put sipPassword into events or rejections.
 */
@ReactModule(name = NativeOmnixVoiceSpec.NAME)
class OmnixVoiceModule(
    reactContext: ReactApplicationContext,
) : NativeOmnixVoiceSpec(reactContext) {
    private var listening: Boolean = false

    private val bridgeListener =
        object : OmnixVoiceListener {
            override fun onRegistrationStateChanged(
                state: OmnixRegistrationState,
                sipCode: Int?,
                reason: String?,
            ) {
                val payload = Arguments.createMap()
                payload.putString("state", state.name)
                if (sipCode != null) {
                    payload.putInt("sipCode", sipCode)
                }
                val safeReason = scrubDetail(reason, null)
                if (safeReason != null) {
                    payload.putString("reason", safeReason)
                }
                emit(EVENT_REGISTRATION, payload)
            }

            override fun onIncomingCall(call: OmnixCallInfo) {
                emit(EVENT_INCOMING, callPayload(call))
            }

            override fun onCallStateChanged(call: OmnixCallInfo) {
                emit(EVENT_CALL_STATE, callPayload(call))
            }

            override fun onAudioRouteChanged(route: OmnixAudioRoute) {
                val payload = Arguments.createMap()
                payload.putString("route", route.name)
                emit(EVENT_AUDIO_ROUTE, payload)
            }

            override fun onError(
                code: OmnixErrorCode,
                detail: String?,
                callId: String?,
            ) {
                val payload = Arguments.createMap()
                payload.putString("code", code.name)
                val safeDetail = scrubDetail(detail, null)
                if (safeDetail != null) {
                    payload.putString("detail", safeDetail)
                }
                if (!callId.isNullOrEmpty()) {
                    payload.putString("callId", callId)
                }
                emit(EVENT_ERROR, payload)
            }
        }

    override fun initialize(
        config: ReadableMap,
        promise: Promise,
    ) {
        val secret = readOptionalString(config, "sipPassword") ?: ""
        try {
            ensureListening()
            OmnixVoice.initialize(reactApplicationContext, readConfig(config, secret))
            promise.resolve(null)
        } catch (error: OmnixVoiceException) {
            if (error.code != OmnixErrorCode.INVALID_CALL_STATE) {
                stopListening()
            }
            reject(promise, error, secret)
        } catch (error: Throwable) {
            stopListening()
            reject(promise, error, secret)
        }
    }

    override fun shutdown(promise: Promise) {
        try {
            stopListening()
            OmnixVoice.shutdown()
            promise.resolve(null)
        } catch (error: Throwable) {
            reject(promise, error, null)
        }
    }

    override fun register(promise: Promise) {
        run(promise) { OmnixVoice.register() }
    }

    override fun unregister(promise: Promise) {
        run(promise) { OmnixVoice.unregister() }
    }

    override fun makeCall(
        destination: String,
        promise: Promise,
    ) {
        try {
            promise.resolve(OmnixVoice.makeCall(destination))
        } catch (error: Throwable) {
            reject(promise, error, null)
        }
    }

    override fun answerCall(
        callId: String,
        promise: Promise,
    ) {
        run(promise) { OmnixVoice.answerCall(callId) }
    }

    override fun rejectCall(
        callId: String,
        promise: Promise,
    ) {
        run(promise) { OmnixVoice.rejectCall(callId) }
    }

    override fun hangupCall(
        callId: String,
        promise: Promise,
    ) {
        run(promise) { OmnixVoice.hangupCall(callId) }
    }

    override fun holdCall(
        callId: String,
        promise: Promise,
    ) {
        run(promise) { OmnixVoice.holdCall(callId) }
    }

    override fun resumeCall(
        callId: String,
        promise: Promise,
    ) {
        run(promise) { OmnixVoice.resumeCall(callId) }
    }

    override fun setMuted(
        callId: String,
        muted: Boolean,
        promise: Promise,
    ) {
        run(promise) { OmnixVoice.setMuted(callId, muted) }
    }

    override fun setSpeakerEnabled(
        enabled: Boolean,
        promise: Promise,
    ) {
        run(promise) { OmnixVoice.setSpeakerEnabled(enabled) }
    }

    override fun sendDTMF(
        callId: String,
        digit: String,
        promise: Promise,
    ) {
        run(promise) {
            if (digit.length != 1) {
                throw OmnixVoiceException(
                    OmnixErrorCode.INVALID_CONFIGURATION,
                    "DTMF digit must be one character",
                )
            }
            OmnixVoice.sendDTMF(callId, digit[0])
        }
    }

    override fun transferCall(
        callId: String,
        destination: String,
        promise: Promise,
    ) {
        run(promise) { OmnixVoice.transferCall(callId, destination) }
    }

    override fun getRegistrationState(promise: Promise) {
        try {
            promise.resolve(OmnixVoice.registrationState.name)
        } catch (error: Throwable) {
            reject(promise, error, null)
        }
    }

    override fun addListener(eventName: String) {
        // NativeEventEmitter reference count. Events are emitted by name.
    }

    override fun removeListeners(count: Double) {
        // NativeEventEmitter reference count. Host listeners are removed in JS.
    }

    private fun ensureListening() {
        if (listening) {
            return
        }
        OmnixVoice.addListener(bridgeListener)
        listening = true
    }

    private fun stopListening() {
        if (!listening) {
            return
        }
        OmnixVoice.removeListener(bridgeListener)
        listening = false
    }

    private fun emit(
        name: String,
        payload: WritableMap,
    ) {
        if (!reactApplicationContext.hasActiveReactInstance()) {
            return
        }
        reactApplicationContext
            .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
            .emit(name, payload)
    }

    private fun run(
        promise: Promise,
        block: () -> Unit,
    ) {
        try {
            block()
            promise.resolve(null)
        } catch (error: Throwable) {
            reject(promise, error, null)
        }
    }

    private fun reject(
        promise: Promise,
        error: Throwable,
        secret: String?,
    ) {
        if (error is OmnixVoiceException) {
            promise.reject(error.code.name, scrubDetail(error.detail, secret) ?: error.code.name)
            return
        }
        promise.reject(
            OmnixErrorCode.INTERNAL_NATIVE_ERROR.name,
            scrubDetail(error.message, secret) ?: OmnixErrorCode.INTERNAL_NATIVE_ERROR.name,
        )
    }

    private companion object {
        const val EVENT_REGISTRATION = "omnixRegistrationStateChanged"
        const val EVENT_INCOMING = "omnixIncomingCall"
        const val EVENT_CALL_STATE = "omnixCallStateChanged"
        const val EVENT_AUDIO_ROUTE = "omnixAudioRouteChanged"
        const val EVENT_ERROR = "omnixError"

        fun callPayload(call: OmnixCallInfo): WritableMap {
            val payload = Arguments.createMap()
            payload.putString("callId", call.callId)
            payload.putString("peerUri", call.peerUri)
            payload.putString("peerDisplayName", call.peerDisplayName)
            payload.putString("state", call.state.name)
            payload.putBoolean("isOutgoing", call.isOutgoing)
            payload.putBoolean("isMuted", call.isMuted)
            payload.putBoolean("isOnHold", call.isOnHold)
            return payload
        }

        fun readConfig(
            config: ReadableMap,
            secret: String,
        ): OmnixVoiceConfig =
            OmnixVoiceConfig(
                sipServer = readRequiredString(config, "sipServer"),
                sipUser = readRequiredString(config, "sipUser"),
                sipPassword = secret,
                authUser = readOptionalString(config, "authUser"),
                displayName = readOptionalString(config, "displayName"),
                stunServer = readOptionalString(config, "stunServer"),
                verifyCert = readBool(config, "verifyCert", true),
                enableSrtp = readBool(config, "enableSrtp", true),
                codecs = readCodecs(config),
            )

        fun readCodecs(config: ReadableMap): List<OmnixCodec> {
            val fallback = listOf(OmnixCodec.OPUS, OmnixCodec.PCMU, OmnixCodec.PCMA)
            val raw = readOptionalString(config, "codecs") ?: return fallback
            val parsed =
                raw.split(',').mapNotNull { token ->
                    val name = token.trim()
                    OmnixCodec.entries.firstOrNull { it.wireName == name }
                }
            return if (parsed.isEmpty()) fallback else parsed
        }

        fun readRequiredString(
            config: ReadableMap,
            key: String,
        ): String = readOptionalString(config, key) ?: ""

        fun readOptionalString(
            config: ReadableMap,
            key: String,
        ): String? {
            if (!config.hasKey(key) || config.isNull(key)) {
                return null
            }
            val value = config.getString(key)
            return if (value.isNullOrEmpty()) null else value
        }

        fun readBool(
            config: ReadableMap,
            key: String,
            defaultValue: Boolean,
        ): Boolean {
            if (!config.hasKey(key) || config.isNull(key)) {
                return defaultValue
            }
            return config.getBoolean(key)
        }

        fun scrubDetail(
            detail: String?,
            secret: String?,
        ): String? {
            if (detail.isNullOrEmpty()) {
                return null
            }
            var out = detail
            if (!secret.isNullOrEmpty() && out.contains(secret)) {
                out = out.replace(secret, "[REDACTED]")
            }
            out =
                Regex(
                    "((?:sipPassword|auth_pass|password)\\s*[:=]\\s*)(\\S+)",
                    RegexOption.IGNORE_CASE,
                ).replace(out, "$1[REDACTED]")
            return if (out.length > 180) out.substring(0, 180) else out
        }
    }
}
