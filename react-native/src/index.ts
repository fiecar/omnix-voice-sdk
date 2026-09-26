/**
 * @omnix/voice-sdk public entry (Issue #1 §19 / §20A, SDK-047).
 *
 * The TurboModule spec stays in NativeOmnixVoice.ts for codegen.
 * It is not part of this public surface.
 */
export type {
  OmnixVoiceConfig,
  OmnixCodec,
  OmnixAudioRoute,
  OmnixRegistrationState,
  OmnixCallState,
  OmnixCallInfo,
  OmnixErrorCode,
  OmnixVoiceEvents,
  IOmnixVoice,
} from './types';

export { OmnixVoiceError } from './errors';
export { OmnixVoice } from './OmnixVoice';
