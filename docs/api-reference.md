# Public API reference

Names match [Issue #1](https://github.com/fiecar/omnix-voice-sdk/issues/1) §20A.
Placeholders only: `sip.example.com`, `user@example.com`.

Credential rule: the host app owns `sipPassword`. The SDK copies it into the stack for digest auth and does not persist it, log it, or put it on events.

`transferCall` is IMPLEMENTED as a stub that fails with `NOT_SUPPORTED`.
Real SIP behavior of register and call methods is NOT AVAILABLE (no test server).
Physical iPhone behavior is NOT AVAILABLE.

## TypeScript — `@omnix/voice-sdk`

Import `OmnixVoice` from `@omnix/voice-sdk`. It is a singleton object, not a class export.
`NativeOmnixVoice` is the codegen contract and is not a public export.

### `OmnixVoiceConfig`

| Field | Notes |
|-------|--------|
| `sipServer` | Example `sips:sip.example.com:5061` |
| `sipUser` | `user` or `user@example.com` |
| `authUser?` | Defaults to the user part of `sipUser` |
| `sipPassword` | Host-owned. Not retained in the JS session fingerprint |
| `displayName?` | |
| `stunServer?` | Optional. TURN URIs are not supported |
| `verifyCert?` | Default `true` |
| `enableSrtp?` | Default `true`. `false` does not disable SRTP |
| `codecs?` | `'opus' \| 'pcmu' \| 'pcma'`. Default `opus`, `pcmu`, `pcma`. Unknown or uncompiled names are dropped. An empty list after filtering is `INVALID_CONFIGURATION` |

### Methods

| Method | Behavior |
|--------|----------|
| `initialize(config)` | Promise. Same non-secret config is idempotent. A different non-secret config while live throws `INVALID_CALL_STATE`. Password-only changes are treated as the same config because the password is not stored. |
| `shutdown()` | Clears JS listeners and, if initialized, asks native to shut down |
| `register()` / `unregister()` | Require initialize |
| `getRegistrationState()` | Synchronous cache updated from events. Starts at `UNINITIALIZED` |
| `makeCall(destination)` | Resolves a call id string. Requires cached `REGISTERED`, otherwise `NOT_REGISTERED` |
| `answerCall` / `rejectCall` / `hangupCall` / `holdCall` / `resumeCall` | `callId` |
| `setMuted(callId, muted)` | |
| `setSpeakerEnabled(enabled)` | |
| `sendDTMF(callId, digit)` | One of `0-9`, `*`, `#`, `A-D` |
| `transferCall(callId, destination)` | Rejects `NOT_SUPPORTED`. Does not call native |
| `getCallInfo(callId)` | Synchronous cache, or `null` |
| `addListener(event, listener)` / `removeListener(event, listener)` | See events. Remove the same function reference |

### States

Registration: `UNINITIALIZED`, `UNREGISTERED`, `REGISTERING`, `REGISTERED`, `REGISTRATION_FAILED`.

Call: `IDLE`, `OUTGOING`, `INCOMING`, `RINGING`, `EARLY_MEDIA`, `CONNECTED`, `HELD`, `ENDING`, `ENDED`, `FAILED`.

Audio route: `EARPIECE`, `SPEAKER`, `WIRED_HEADSET`, `BLUETOOTH`, `UNKNOWN`.

### Events

| Event | Payload |
|-------|---------|
| `registrationStateChanged` | `(state, sipCode?, reason?)` |
| `incomingCall` | `OmnixCallInfo` |
| `callStateChanged` | `OmnixCallInfo` |
| `audioRouteChanged` | `OmnixAudioRoute` |
| `error` | `OmnixVoiceError` (`code`, `detail?`, `callId?`) |

`OmnixCallInfo`: `callId`, `peerUri`, `peerDisplayName?`, `state`, `isOutgoing`, `isMuted`, `isOnHold`, `durationSeconds?`.

### Error codes

`INITIALIZATION_ERROR`, `INVALID_CONFIGURATION`, `REGISTRATION_FAILED`, `AUTHENTICATION_FAILED`, `NETWORK_UNAVAILABLE`, `TLS_ERROR`, `MEDIA_ERROR`, `CALL_FAILED`, `CALL_BUSY`, `CALL_REJECTED`, `TIMEOUT`, `NOT_REGISTERED`, `INVALID_CALL_STATE`, `PERMISSION_DENIED`, `TRANSFER_FAILED`, `NOT_SUPPORTED`, `INTERNAL_NATIVE_ERROR`.

These are Omnix codes. Raw Baresip codes, `errno`, JNI exceptions, and `NSError` domains are not part of this API.

## C — `omnix_voice.h`

`omnix_init`, `omnix_shutdown`, `omnix_register`, `omnix_unregister`, `omnix_get_reg_state`, `omnix_call_make`, `omnix_call_answer`, `omnix_call_reject`, `omnix_call_hangup`, `omnix_call_hold`, `omnix_call_resume`, `omnix_call_set_mute`, `omnix_call_set_speaker`, `omnix_call_send_dtmf`, `omnix_call_transfer_blind`, `omnix_call_get_state`.

The header includes only `omnix_types.h`. C registration failure is `OMNIX_REG_FAILED`; Kotlin, Swift, and TypeScript map that to `REGISTRATION_FAILED`.

## Android — `com.omnix.voice.OmnixVoice`

Kotlin object. `initialize(context, config)` throws `OmnixVoiceException` and checks `RECORD_AUDIO`.
`registrationState` is a property. `getCallInfo(callId)` returns `OmnixCallInfo?`.
`sendDTMF` takes a `Char`. `transferCall` throws `NOT_SUPPORTED`.
Events: `OmnixVoiceListener` (`onRegistrationStateChanged`, `onIncomingCall`, `onCallStateChanged`, `onAudioRouteChanged`, `onError`).

The React Native module `com.omnix.voice.rn.OmnixVoiceModule` calls this object only. It is not a second public SIP API.

## iOS — `OmnixVoice`

Swift. `initialize(config:)` throws. `registrationState` is a property. `callInfo(callId:)` returns `OmnixCallInfo?`.
`sendDTMF` takes a `Character`. `transferCall` throws `NOT_SUPPORTED`.
Delegate: `OmnixVoiceDelegate` (`registrationStateChanged`, `incomingCall`, `callStateChanged`, `audioRouteChanged`, `didReceiveError`).

Source compiles in the iOS static CI job. That job does not produce or validate an XCFramework. XCFramework packaging is BLOCKED.
