/**
 * TurboModule codegen spec for Omnix Voice (New Architecture only).
 * Module name must match native: OmnixVoiceModule.
 * Full TS facade lands in SDK-047; this file is the codegen contract (SDK-046).
 *
 * Placeholders only — never embed real SIP credentials.
 */
import type { TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';

export type OmnixNativeConfig = {
  sipServer: string;
  sipUser: string;
  sipPassword: string;
  authUser?: string | null;
  displayName?: string | null;
  stunServer?: string | null;
  verifyCert?: boolean;
  enableSrtp?: boolean;
  codecs?: string | null;
};

export interface Spec extends TurboModule {
  initialize(config: OmnixNativeConfig): Promise<void>;
  shutdown(): Promise<void>;
  register(): Promise<void>;
  unregister(): Promise<void>;
  makeCall(destination: string): Promise<string>;
  answerCall(callId: string): Promise<void>;
  rejectCall(callId: string): Promise<void>;
  hangupCall(callId: string): Promise<void>;
  holdCall(callId: string): Promise<void>;
  resumeCall(callId: string): Promise<void>;
  setMuted(callId: string, muted: boolean): Promise<void>;
  setSpeakerEnabled(enabled: boolean): Promise<void>;
  sendDTMF(callId: string, digit: string): Promise<void>;
  transferCall(callId: string, destination: string): Promise<void>;
  getRegistrationState(): Promise<string>;
  // EventEmitter contract (RN requires these for NativeEventEmitter).
  addListener(eventName: string): void;
  removeListeners(count: number): void;
}

export default TurboModuleRegistry.getEnforcing<Spec>('OmnixVoiceModule');
