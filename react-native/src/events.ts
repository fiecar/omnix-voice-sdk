/**
 * Native event names and payload checks (Issue #1 §20A.5).
 * These strings are the bridge contract. They are not part of the public barrel.
 */
import { OmnixVoiceError, isOmnixErrorCode, scrubDetail } from './errors';
import type {
  OmnixAudioRoute,
  OmnixCallInfo,
  OmnixCallState,
  OmnixRegistrationState,
} from './types';

export const OMNIX_NATIVE_EVENT = {
  registrationStateChanged: 'omnixRegistrationStateChanged',
  incomingCall: 'omnixIncomingCall',
  callStateChanged: 'omnixCallStateChanged',
  audioRouteChanged: 'omnixAudioRouteChanged',
  error: 'omnixError',
} as const;

const REGISTRATION_STATES: readonly OmnixRegistrationState[] = [
  'UNINITIALIZED',
  'UNREGISTERED',
  'REGISTERING',
  'REGISTERED',
  'REGISTRATION_FAILED',
];

const CALL_STATES: readonly OmnixCallState[] = [
  'IDLE',
  'OUTGOING',
  'INCOMING',
  'RINGING',
  'EARLY_MEDIA',
  'CONNECTED',
  'HELD',
  'ENDING',
  'ENDED',
  'FAILED',
];

const AUDIO_ROUTES: readonly OmnixAudioRoute[] = [
  'EARPIECE',
  'SPEAKER',
  'WIRED_HEADSET',
  'BLUETOOTH',
  'UNKNOWN',
];

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

function isOneOf<T extends string>(
  value: unknown,
  allowed: readonly T[],
): value is T {
  return typeof value === 'string' && (allowed as readonly string[]).includes(value);
}

export type RegistrationEvent = {
  state: OmnixRegistrationState;
  sipCode?: number;
  reason?: string;
};

export function parseRegistrationEvent(
  value: unknown,
): RegistrationEvent | null {
  if (!isRecord(value) || !isOneOf(value.state, REGISTRATION_STATES)) {
    return null;
  }
  const parsed: RegistrationEvent = { state: value.state };
  if (value.sipCode !== undefined && value.sipCode !== null) {
    if (typeof value.sipCode !== 'number' || !Number.isFinite(value.sipCode)) {
      return null;
    }
    parsed.sipCode = value.sipCode;
  }
  if (value.reason !== undefined && value.reason !== null) {
    if (typeof value.reason !== 'string') {
      return null;
    }
    const reason = scrubDetail(value.reason);
    if (reason !== undefined) {
      parsed.reason = reason;
    }
  }
  return parsed;
}

export function parseCallInfo(value: unknown): OmnixCallInfo | null {
  if (!isRecord(value)) {
    return null;
  }
  if (typeof value.callId !== 'string' || value.callId.length === 0) {
    return null;
  }
  if (typeof value.peerUri !== 'string') {
    return null;
  }
  if (!isOneOf(value.state, CALL_STATES)) {
    return null;
  }
  if (
    typeof value.isOutgoing !== 'boolean' ||
    typeof value.isMuted !== 'boolean' ||
    typeof value.isOnHold !== 'boolean'
  ) {
    return null;
  }
  const info: OmnixCallInfo = {
    callId: value.callId,
    peerUri: value.peerUri,
    state: value.state,
    isOutgoing: value.isOutgoing,
    isMuted: value.isMuted,
    isOnHold: value.isOnHold,
  };
  if (typeof value.peerDisplayName === 'string') {
    info.peerDisplayName = scrubDetail(value.peerDisplayName);
  }
  if (
    typeof value.durationSeconds === 'number' &&
    Number.isFinite(value.durationSeconds)
  ) {
    info.durationSeconds = value.durationSeconds;
  }
  return info;
}

export function parseAudioRoute(value: unknown): OmnixAudioRoute | null {
  if (!isRecord(value) || !isOneOf(value.route, AUDIO_ROUTES)) {
    return null;
  }
  return value.route;
}

export function parseErrorEvent(value: unknown): OmnixVoiceError | null {
  if (!isRecord(value) || typeof value.code !== 'string') {
    return null;
  }
  if (!isOmnixErrorCode(value.code)) {
    return null;
  }
  const detail =
    typeof value.detail === 'string' ? scrubDetail(value.detail) : undefined;
  const callId =
    typeof value.callId === 'string' && value.callId.length > 0
      ? value.callId
      : undefined;
  return new OmnixVoiceError(value.code, detail, callId);
}
