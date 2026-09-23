# Android integration guide

Host-app requirements for consuming the Omnix Voice Android AAR (MVP).

Placeholders only in examples: `sip.example.com`, `user@example.com`.
Never put real SIP passwords, tokens, or customer hostnames in source or docs.

## Consuming the release AAR (SDK-036)

Build artifact name: `OmnixVoiceSDK-x.y.z.aar` (e.g. `OmnixVoiceSDK-0.1.0.aar`).
It ships the three ABI `libomnixvoice.so` libraries, Kotlin classes, the merged
manifest permissions below, and `assets/THIRD_PARTY_NOTICES.md` (must ship with
binary distributions — see repo-root `THIRD_PARTY_NOTICES.md` / `LICENSES/`).

## Permissions (SDK-033)

### Manifest (merge)

The AAR declares:

- `android.permission.RECORD_AUDIO` — required for capture
- `android.permission.INTERNET`
- `android.permission.ACCESS_NETWORK_STATE`

These merge into the host app manifest automatically. Do **not** add
foreground-service / Bluetooth / notification permissions for MVP (Phase 2).

### Runtime request (host responsibility)

On Android 6+ (`minSdk` 26 for this SDK), `RECORD_AUDIO` is a **dangerous**
permission. The **host application** must request it from the user
(e.g. `ActivityResultContracts.RequestPermission` or
`ActivityCompat.requestPermissions`) **before** calling
`OmnixVoice.initialize(...)`.

The SDK does **not** show a system permission dialog.

### SDK check in `initialize()`

`OmnixVoice.initialize(context, config)`:

1. Checks `RECORD_AUDIO` via `Context.checkSelfPermission`.
2. If **not** granted:
   - Fires `OmnixVoiceListener.onError(PERMISSION_DENIED, …)`
   - Throws `OmnixVoiceException` with `OmnixErrorCode.PERMISSION_DENIED`
   - Does **not** call into native / does **not** mark the SDK initialized
3. If granted, proceeds with native init (password still never persisted).

Recommended host order:

1. Ensure `RECORD_AUDIO` is granted (request UI if needed).
2. `OmnixVoice.addListener(…)` (optional; catches the permission error event).
3. `OmnixVoice.initialize(applicationContext, config)`.
4. `OmnixVoice.register()` when ready.

## Audio focus and routing (SDK-034)

The SDK owns call-time audio session setup via internal `OmnixAudioRouter`:

| Moment | Behavior |
|--------|----------|
| Call start (first active call state) | Request `AUDIOFOCUS_GAIN_TRANSIENT` with `AudioAttributes.USAGE_VOICE_COMMUNICATION`; set `AudioManager.MODE_IN_COMMUNICATION` |
| `OmnixVoice.setSpeakerEnabled(true/false)` | `AudioManager.setSpeakerphoneOn` (also stored in the C facade from SDK-021); fires `onAudioRouteChanged` |
| Call end (no remaining active calls) | Abandon audio focus; clear speakerphone; restore prior audio mode |
| `shutdown()` | Ends any active call audio session |

Host apps should **not** fight the SDK for `MODE_IN_COMMUNICATION` during a call.
Bluetooth / wired-headset auto-routing beyond speaker vs earpiece is MVP-limited
(`OmnixAudioRoute.WIRED_HEADSET` / `BLUETOOTH` exist in the enum for later work).

## Credentials

The SDK may **receive** SIP credentials at runtime. It does **not** persist
them (no `SharedPreferences` / files). Long-term storage is the host app’s
job. Never log `sipPassword`.

## MVP incoming-call limit

Incoming calls are supported only while the app process is alive and in a
supported foreground lifecycle. Background / killed-app telephony is Phase 2
(see Issue #1 §0.1).
