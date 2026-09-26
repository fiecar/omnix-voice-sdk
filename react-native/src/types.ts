/**
 * Public TypeScript types for @omnix/voice-sdk (Issue #1 §19 / §20A).
 *
 * Credential persistence is the host app's responsibility. This SDK accepts
 * `sipPassword` only to pass it into `initialize()` and does not store it,
 * log it, or copy it into errors or events.
 *
 * No Baresip/re types belong in this module.
 */
import type { OmnixVoiceError } from './errors';

export type OmnixVoiceConfig = {
  /** Example: "sips:sip.example.com:5061". */
  sipServer: string;
  /** "user" or "user@example.com". */
  sipUser: string;
  /** Default: user part of sipUser. */
  authUser?: string;
  /**
   * Host-owned credential. Never logged, never persisted by the SDK,
   * never echoed in events or errors.
   */
  sipPassword: string;
  displayName?: string;
  /** MVP SHOULD (F-8). */
  stunServer?: string;
  /** Default: true. */
  verifyCert?: boolean;
  /** Default: true. */
  enableSrtp?: boolean;
  /** Default: ['opus', 'pcmu', 'pcma']. Unavailable entries are ignored. */
  codecs?: OmnixCodec[];
};

export type OmnixCodec = 'opus' | 'pcmu' | 'pcma';

export type OmnixAudioRoute =
  | 'EARPIECE'
  | 'SPEAKER'
  | 'WIRED_HEADSET'
  | 'BLUETOOTH'
  | 'UNKNOWN';

export type OmnixRegistrationState =
  | 'UNINITIALIZED'
  | 'UNREGISTERED'
  | 'REGISTERING'
  | 'REGISTERED'
  | 'REGISTRATION_FAILED';

export type OmnixCallState =
  | 'IDLE'
  | 'OUTGOING'
  | 'INCOMING'
  | 'RINGING'
  | 'EARLY_MEDIA'
  | 'CONNECTED'
  | 'HELD'
  | 'ENDING'
  | 'ENDED'
  | 'FAILED';

export type OmnixCallInfo = {
  callId: string;
  peerUri: string;
  peerDisplayName?: string;
  state: OmnixCallState;
  isOutgoing: boolean;
  isMuted: boolean;
  isOnHold: boolean;
  durationSeconds?: number;
};

export type OmnixErrorCode =
  | 'INITIALIZATION_ERROR'
  | 'INVALID_CONFIGURATION'
  | 'REGISTRATION_FAILED'
  | 'AUTHENTICATION_FAILED'
  | 'NETWORK_UNAVAILABLE'
  | 'TLS_ERROR'
  | 'MEDIA_ERROR'
  | 'CALL_FAILED'
  | 'CALL_BUSY'
  | 'CALL_REJECTED'
  | 'TIMEOUT'
  | 'NOT_REGISTERED'
  | 'INVALID_CALL_STATE'
  | 'PERMISSION_DENIED'
  | 'TRANSFER_FAILED'
  | 'NOT_SUPPORTED'
  | 'INTERNAL_NATIVE_ERROR';

export type OmnixVoiceEvents = {
  registrationStateChanged: (
    state: OmnixRegistrationState,
    sipCode?: number,
    reason?: string,
  ) => void;
  incomingCall: (call: OmnixCallInfo) => void;
  callStateChanged: (call: OmnixCallInfo) => void;
  audioRouteChanged: (route: OmnixAudioRoute) => void;
  error: (err: OmnixVoiceError) => void;
};

export interface IOmnixVoice {
  initialize(config: OmnixVoiceConfig): Promise<void>;
  shutdown(): Promise<void>;
  register(): Promise<void>;
  unregister(): Promise<void>;
  /** JS-side cache updated from events. No synchronous native call. */
  getRegistrationState(): OmnixRegistrationState;
  makeCall(destination: string): Promise<string>;
  answerCall(callId: string): Promise<void>;
  rejectCall(callId: string): Promise<void>;
  hangupCall(callId: string): Promise<void>;
  holdCall(callId: string): Promise<void>;
  resumeCall(callId: string): Promise<void>;
  setMuted(callId: string, muted: boolean): Promise<void>;
  setSpeakerEnabled(enabled: boolean): Promise<void>;
  sendDTMF(callId: string, digit: string): Promise<void>;
  /** Blind transfer. Rejects NOT_SUPPORTED until SDK-024. */
  transferCall(callId: string, destination: string): Promise<void>;
  /** JS-side cache. */
  getCallInfo(callId: string): OmnixCallInfo | null;
  addListener<K extends keyof OmnixVoiceEvents>(
    event: K,
    listener: OmnixVoiceEvents[K],
  ): void;
  removeListener<K extends keyof OmnixVoiceEvents>(
    event: K,
    listener: OmnixVoiceEvents[K],
  ): void;
}
