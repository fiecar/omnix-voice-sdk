/**
 * Public OmnixVoice singleton (Issue #1 §20A.1 / SDK-047).
 *
 * Talks only to the codegen TurboModule. Registration and call snapshots are
 * cached from native events. SIP passwords are passed to initialize() and
 * then dropped; credential persistence stays with the host app.
 */
import { NativeEventEmitter } from 'react-native';
import { toOmnixError, OmnixVoiceError } from './errors';
import {
  OMNIX_NATIVE_EVENT,
  parseAudioRoute,
  parseCallInfo,
  parseErrorEvent,
  parseRegistrationEvent,
} from './events';
import NativeOmnixVoice from './NativeOmnixVoice';
import type { OmnixNativeConfig } from './NativeOmnixVoice';
import type {
  IOmnixVoice,
  OmnixCallInfo,
  OmnixCodec,
  OmnixRegistrationState,
  OmnixVoiceConfig,
  OmnixVoiceEvents,
} from './types';

const DEFAULT_CODECS: readonly OmnixCodec[] = ['opus', 'pcmu', 'pcma'];
const DTMF_DIGIT = /^[0-9*#A-D]$/i;

type Removable = { remove(): void };

function isCodec(value: string): value is OmnixCodec {
  return value === 'opus' || value === 'pcmu' || value === 'pcma';
}

function normalizeCodecs(codecs: readonly string[] | undefined): OmnixCodec[] {
  const source = codecs ?? DEFAULT_CODECS;
  const out: OmnixCodec[] = [];
  for (const item of source) {
    if (isCodec(item) && !out.includes(item)) {
      out.push(item);
    }
  }
  if (out.length === 0) {
    throw new OmnixVoiceError(
      'INVALID_CONFIGURATION',
      'no supported codecs',
    );
  }
  return out;
}

/**
 * Non-secret identity of a session. The password is intentionally absent:
 * the TS layer must not retain it after initialize() returns, so a later
 * call cannot tell a password-only change from the same configuration.
 */
function sessionFingerprint(config: OmnixVoiceConfig): string {
  const codecs = normalizeCodecs(config.codecs);
  return JSON.stringify({
    sipServer: config.sipServer,
    sipUser: config.sipUser,
    authUser: config.authUser ?? null,
    displayName: config.displayName ?? null,
    stunServer: config.stunServer ?? null,
    verifyCert: config.verifyCert ?? true,
    enableSrtp: config.enableSrtp ?? true,
    codecs,
  });
}

function orNull(value: string | null | undefined): string | null {
  if (value == null || value === '') {
    return null;
  }
  return value;
}

class OmnixVoiceClient implements IOmnixVoice {
  private registrationState: OmnixRegistrationState = 'UNINITIALIZED';
  private readonly calls = new Map<string, OmnixCallInfo>();
  private ready = false;
  private sessionKey: string | null = null;
  private tail: Promise<void> = Promise.resolve();
  private subscriptions: Removable[] = [];
  private readonly listeners: {
    [K in keyof OmnixVoiceEvents]: Set<OmnixVoiceEvents[K]>;
  } = {
    registrationStateChanged: new Set(),
    incomingCall: new Set(),
    callStateChanged: new Set(),
    audioRouteChanged: new Set(),
    error: new Set(),
  };

  initialize(config: OmnixVoiceConfig): Promise<void> {
    return this.enqueue(() => this.doInitialize(config));
  }

  /**
   * Releases native resources, drops cached call state, and removes listeners
   * so a shut-down SDK does not retain host callbacks.
   */
  shutdown(): Promise<void> {
    return this.enqueue(() => this.doShutdown());
  }

  register(): Promise<void> {
    return this.enqueue(() => this.invoke(() => NativeOmnixVoice.register()));
  }

  unregister(): Promise<void> {
    return this.enqueue(() =>
      this.invoke(() => NativeOmnixVoice.unregister()),
    );
  }

  getRegistrationState(): OmnixRegistrationState {
    return this.registrationState;
  }

  makeCall(destination: string): Promise<string> {
    return this.enqueue(() => this.doMakeCall(destination));
  }

  answerCall(callId: string): Promise<void> {
    return this.enqueue(() =>
      this.invokeCall(callId, (id) => NativeOmnixVoice.answerCall(id)),
    );
  }

  rejectCall(callId: string): Promise<void> {
    return this.enqueue(() =>
      this.invokeCall(callId, (id) => NativeOmnixVoice.rejectCall(id)),
    );
  }

  hangupCall(callId: string): Promise<void> {
    return this.enqueue(() =>
      this.invokeCall(callId, (id) => NativeOmnixVoice.hangupCall(id)),
    );
  }

  holdCall(callId: string): Promise<void> {
    return this.enqueue(() =>
      this.invokeCall(callId, (id) => NativeOmnixVoice.holdCall(id)),
    );
  }

  resumeCall(callId: string): Promise<void> {
    return this.enqueue(() =>
      this.invokeCall(callId, (id) => NativeOmnixVoice.resumeCall(id)),
    );
  }

  setMuted(callId: string, muted: boolean): Promise<void> {
    return this.enqueue(() =>
      this.invokeCall(callId, (id) => NativeOmnixVoice.setMuted(id, muted)),
    );
  }

  setSpeakerEnabled(enabled: boolean): Promise<void> {
    return this.enqueue(() =>
      this.invoke(() => NativeOmnixVoice.setSpeakerEnabled(enabled)),
    );
  }

  sendDTMF(callId: string, digit: string): Promise<void> {
    return this.enqueue(() => this.doSendDtmf(callId, digit));
  }

  transferCall(callId: string, destination: string): Promise<void> {
    if (callId.trim() === '' || destination.trim() === '') {
      return Promise.reject(
        new OmnixVoiceError(
          'INVALID_CONFIGURATION',
          'callId and destination are required',
        ),
      );
    }
    return Promise.reject(
      new OmnixVoiceError(
        'NOT_SUPPORTED',
        'blind transfer requires SDK-024',
      ),
    );
  }

  getCallInfo(callId: string): OmnixCallInfo | null {
    const info = this.calls.get(callId);
    return info ? { ...info } : null;
  }

  addListener<K extends keyof OmnixVoiceEvents>(
    event: K,
    listener: OmnixVoiceEvents[K],
  ): void {
    this.listeners[event].add(listener);
  }

  removeListener<K extends keyof OmnixVoiceEvents>(
    event: K,
    listener: OmnixVoiceEvents[K],
  ): void {
    this.listeners[event].delete(listener);
  }

  private enqueue<T>(work: () => Promise<T>): Promise<T> {
    const run = this.tail.then(work, work);
    this.tail = run.then(
      () => undefined,
      () => undefined,
    );
    return run;
  }

  private async doInitialize(config: OmnixVoiceConfig): Promise<void> {
    if (config.sipServer.trim() === '' || config.sipUser.trim() === '') {
      throw new OmnixVoiceError(
        'INVALID_CONFIGURATION',
        'sipServer and sipUser are required',
      );
    }
    const nextKey = sessionFingerprint(config);
    if (this.ready) {
      if (this.sessionKey === nextKey) {
        return;
      }
      throw new OmnixVoiceError(
        'INVALID_CALL_STATE',
        'already initialized',
      );
    }

    const sipPassword = config.sipPassword;
    const nativeConfig: OmnixNativeConfig = {
      sipServer: config.sipServer,
      sipUser: config.sipUser,
      sipPassword,
      authUser: orNull(config.authUser),
      displayName: orNull(config.displayName),
      stunServer: orNull(config.stunServer),
      verifyCert: config.verifyCert ?? true,
      enableSrtp: config.enableSrtp ?? true,
      codecs: normalizeCodecs(config.codecs).join(','),
    };

    if (NativeOmnixVoice == null) {
      throw new OmnixVoiceError(
        'INITIALIZATION_ERROR',
        'native module unavailable',
      );
    }

    this.attachEvents();
    try {
      await NativeOmnixVoice.initialize(nativeConfig);
    } catch (error: unknown) {
      this.detachEvents();
      throw toOmnixError(error, sipPassword);
    }

    this.ready = true;
    this.sessionKey = nextKey;
    this.registrationState = 'UNREGISTERED';
    this.attachEvents();
  }

  private async doShutdown(): Promise<void> {
    const wasReady = this.ready;
    this.detachEvents();
    this.clearListeners();
    this.calls.clear();
    this.registrationState = 'UNINITIALIZED';
    this.ready = false;
    this.sessionKey = null;
    if (!wasReady || NativeOmnixVoice == null) {
      return;
    }
    try {
      await NativeOmnixVoice.shutdown();
    } catch (error: unknown) {
      throw toOmnixError(error);
    }
  }

  private async doMakeCall(destination: string): Promise<string> {
    this.ensureReady();
    if (destination.trim() === '') {
      throw new OmnixVoiceError(
        'INVALID_CONFIGURATION',
        'destination is required',
      );
    }
    if (this.registrationState !== 'REGISTERED') {
      throw new OmnixVoiceError(
        'NOT_REGISTERED',
        'register before making a call',
      );
    }
    try {
      const callId = await NativeOmnixVoice.makeCall(destination);
      if (typeof callId !== 'string' || callId.length === 0) {
        throw new OmnixVoiceError('CALL_FAILED', 'makeCall failed');
      }
      return callId;
    } catch (error: unknown) {
      if (error instanceof OmnixVoiceError) {
        throw error;
      }
      throw toOmnixError(error);
    }
  }

  private async doSendDtmf(callId: string, digit: string): Promise<void> {
    this.ensureReady();
    this.requireCallId(callId);
    if (!DTMF_DIGIT.test(digit)) {
      throw new OmnixVoiceError(
        'INVALID_CONFIGURATION',
        'DTMF digit must be 0-9, *, #, or A-D',
      );
    }
    await this.invoke(() =>
      NativeOmnixVoice.sendDTMF(callId, digit.toUpperCase()),
    );
  }

  private async invoke(work: () => Promise<void>): Promise<void> {
    this.ensureReady();
    try {
      await work();
    } catch (error: unknown) {
      throw toOmnixError(error);
    }
  }

  private async invokeCall(
    callId: string,
    work: (id: string) => Promise<void>,
  ): Promise<void> {
    this.ensureReady();
    const id = this.requireCallId(callId);
    try {
      await work(id);
    } catch (error: unknown) {
      throw toOmnixError(error);
    }
  }

  private ensureReady(): void {
    if (!this.ready) {
      throw new OmnixVoiceError('INVALID_CALL_STATE', 'SDK not initialized');
    }
  }

  private requireCallId(callId: string): string {
    if (callId.trim() === '') {
      throw new OmnixVoiceError(
        'INVALID_CONFIGURATION',
        'callId is required',
      );
    }
    return callId;
  }

  private attachEvents(): void {
    if (this.subscriptions.length > 0 || NativeOmnixVoice == null) {
      return;
    }
    const emitter = new NativeEventEmitter(NativeOmnixVoice);
    const bindings: ReadonlyArray<readonly [string, (payload: unknown) => void]> =
      [
        [
          OMNIX_NATIVE_EVENT.registrationStateChanged,
          (payload) => this.onRegistration(payload),
        ],
        [OMNIX_NATIVE_EVENT.incomingCall, (payload) => this.onIncoming(payload)],
        [
          OMNIX_NATIVE_EVENT.callStateChanged,
          (payload) => this.onCallState(payload),
        ],
        [
          OMNIX_NATIVE_EVENT.audioRouteChanged,
          (payload) => this.onAudioRoute(payload),
        ],
        [OMNIX_NATIVE_EVENT.error, (payload) => this.onNativeError(payload)],
      ];
    for (const [name, handler] of bindings) {
      this.subscriptions.push(emitter.addListener(name, handler));
    }
  }

  private detachEvents(): void {
    for (const subscription of this.subscriptions) {
      subscription.remove();
    }
    this.subscriptions = [];
  }

  private clearListeners(): void {
    (Object.keys(this.listeners) as Array<keyof OmnixVoiceEvents>).forEach(
      (event) => {
        this.listeners[event].clear();
      },
    );
  }

  private onRegistration(payload: unknown): void {
    const parsed = parseRegistrationEvent(payload);
    if (!parsed) {
      this.emitInvalidPayload();
      return;
    }
    this.registrationState = parsed.state;
    this.emit(
      'registrationStateChanged',
      parsed.state,
      parsed.sipCode,
      parsed.reason,
    );
  }

  private onIncoming(payload: unknown): void {
    const info = parseCallInfo(payload);
    if (!info) {
      this.emitInvalidPayload();
      return;
    }
    this.calls.set(info.callId, info);
    this.emit('incomingCall', { ...info });
  }

  private onCallState(payload: unknown): void {
    const info = parseCallInfo(payload);
    if (!info) {
      this.emitInvalidPayload();
      return;
    }
    this.calls.set(info.callId, info);
    this.emit('callStateChanged', { ...info });
  }

  private onAudioRoute(payload: unknown): void {
    const route = parseAudioRoute(payload);
    if (!route) {
      this.emitInvalidPayload();
      return;
    }
    this.emit('audioRouteChanged', route);
  }

  private onNativeError(payload: unknown): void {
    const parsed = parseErrorEvent(payload);
    if (!parsed) {
      this.emitInvalidPayload();
      return;
    }
    this.emit('error', parsed);
  }

  private emitInvalidPayload(): void {
    this.emit(
      'error',
      new OmnixVoiceError('INTERNAL_NATIVE_ERROR', 'invalid native event'),
    );
  }

  private emit<K extends keyof OmnixVoiceEvents>(
    event: K,
    ...args: Parameters<OmnixVoiceEvents[K]>
  ): void {
    const snapshot = [...this.listeners[event]];
    for (const listener of snapshot) {
      try {
        (listener as (...passed: Parameters<OmnixVoiceEvents[K]>) => void)(
          ...args,
        );
      } catch {
        // Host listener failed. Do not log: event payloads must not reach console.
      }
    }
  }
}

/** Default singleton implementing IOmnixVoice. */
export const OmnixVoice: IOmnixVoice = new OmnixVoiceClient();
