/**
 * SDK-047: mocked TurboModule and fake event emitter. No SIP server.
 */
import * as ReactNative from 'react-native';
import { OmnixVoice, OmnixVoiceError } from '../index';
import type { OmnixCallInfo, OmnixVoiceConfig } from '../types';
import NativeOmnixVoice from '../NativeOmnixVoice';

const SECRET = 'omnix-test-secret-9f3a';

type NativeMock = {
  initialize: jest.Mock;
  shutdown: jest.Mock;
  register: jest.Mock;
  unregister: jest.Mock;
  makeCall: jest.Mock;
  answerCall: jest.Mock;
  rejectCall: jest.Mock;
  hangupCall: jest.Mock;
  holdCall: jest.Mock;
  resumeCall: jest.Mock;
  setMuted: jest.Mock;
  setSpeakerEnabled: jest.Mock;
  sendDTMF: jest.Mock;
  transferCall: jest.Mock;
  getRegistrationState: jest.Mock;
  addListener: jest.Mock;
  removeListeners: jest.Mock;
};

type TestReactNative = typeof ReactNative & {
  __omnixEmit: (event: string, payload: unknown) => void;
};

function emit(event: string, payload: unknown): void {
  (ReactNative as TestReactNative).__omnixEmit(event, payload);
}

function native(): NativeMock {
  return NativeOmnixVoice as unknown as NativeMock;
}

function sampleConfig(
  overrides: Partial<OmnixVoiceConfig> = {},
): OmnixVoiceConfig {
  return {
    sipServer: 'sips:sip.example.com:5061',
    sipUser: 'user@example.com',
    sipPassword: SECRET,
    ...overrides,
  };
}

const consoleMethods = ['log', 'info', 'warn', 'error', 'debug'] as const;

jest.mock('../NativeOmnixVoice', () => ({
  __esModule: true,
  default: {
    initialize: jest.fn(async () => undefined),
    shutdown: jest.fn(async () => undefined),
    register: jest.fn(async () => undefined),
    unregister: jest.fn(async () => undefined),
    makeCall: jest.fn(async () => 'call-1'),
    answerCall: jest.fn(async () => undefined),
    rejectCall: jest.fn(async () => undefined),
    hangupCall: jest.fn(async () => undefined),
    holdCall: jest.fn(async () => undefined),
    resumeCall: jest.fn(async () => undefined),
    setMuted: jest.fn(async () => undefined),
    setSpeakerEnabled: jest.fn(async () => undefined),
    sendDTMF: jest.fn(async () => undefined),
    transferCall: jest.fn(async () => undefined),
    getRegistrationState: jest.fn(async () => 'UNREGISTERED'),
    addListener: jest.fn(),
    removeListeners: jest.fn(),
  },
}));

jest.mock('react-native', () => {
  const listeners = new Map<string, Set<(payload: unknown) => void>>();

  class NativeEventEmitter {
    private readonly nativeModule: {
      addListener?: (event: string) => void;
      removeListeners?: (count: number) => void;
    } | null;

    constructor(
      nativeModule?: {
        addListener?: (event: string) => void;
        removeListeners?: (count: number) => void;
      } | null,
    ) {
      this.nativeModule = nativeModule ?? null;
    }

    addListener(event: string, listener: (payload: unknown) => void): {
      remove: () => void;
    } {
      this.nativeModule?.addListener?.(event);
      let bucket = listeners.get(event);
      if (!bucket) {
        bucket = new Set();
        listeners.set(event, bucket);
      }
      bucket.add(listener);
      return {
        remove: () => {
          bucket?.delete(listener);
          this.nativeModule?.removeListeners?.(1);
        },
      };
    }
  }

  return {
    NativeEventEmitter,
    TurboModuleRegistry: {
      getEnforcing: () => {
        throw new Error('codegen module must be mocked');
      },
    },
    __omnixEmit(event: string, payload: unknown): void {
      const bucket = listeners.get(event);
      if (!bucket) {
        return;
      }
      for (const listener of [...bucket]) {
        listener(payload);
      }
    },
  };
});

describe('OmnixVoice', () => {
  const spies = consoleMethods.map((method) =>
    jest.spyOn(console, method).mockImplementation(() => undefined),
  );

  beforeEach(() => {
    jest.clearAllMocks();
  });

  afterEach(async () => {
    await OmnixVoice.shutdown();
    for (const spy of spies) {
      spy.mockClear();
    }
  });

  afterAll(() => {
    for (const spy of spies) {
      spy.mockRestore();
    }
  });

  function consoleText(): string {
    return spies
      .flatMap((spy) => spy.mock.calls)
      .flat()
      .map((part) => {
        if (typeof part === 'string') {
          return part;
        }
        try {
          return JSON.stringify(part);
        } catch {
          return String(part);
        }
      })
      .join('\n');
  }

  it('does not pass sipPassword to console and does not keep it on the singleton', async () => {
    await OmnixVoice.initialize(sampleConfig());

    expect(native().initialize).toHaveBeenCalledWith(
      expect.objectContaining({ sipPassword: SECRET }),
    );
    expect(consoleText()).not.toContain(SECRET);
    expect(JSON.stringify(OmnixVoice)).not.toContain(SECRET);
    expect(OmnixVoice.getRegistrationState()).toBe('UNREGISTERED');
  });

  it('scrubs the password out of an initialize rejection', async () => {
    native().initialize.mockRejectedValueOnce(
      new Error(`register failed ${SECRET} password=${SECRET}`),
    );

    let caught: unknown;
    try {
      await OmnixVoice.initialize(sampleConfig());
    } catch (error: unknown) {
      caught = error;
    }

    expect(caught).toBeInstanceOf(OmnixVoiceError);
    const voiceError = caught as OmnixVoiceError;
    expect(voiceError.code).toBe('INTERNAL_NATIVE_ERROR');
    expect(voiceError.message).not.toContain(SECRET);
    expect(voiceError.detail ?? '').not.toContain(SECRET);
    expect(voiceError.detail ?? '').toContain('[REDACTED]');
    expect(consoleText()).not.toContain(SECRET);
    expect(native().removeListeners).toHaveBeenCalled();
    expect(OmnixVoice.getRegistrationState()).toBe('UNINITIALIZED');
  });

  it('treats the same non-secret config as idempotent and rejects a different one', async () => {
    await OmnixVoice.initialize(sampleConfig());
    await OmnixVoice.initialize(
      sampleConfig({ sipPassword: 'different-value-not-stored' }),
    );
    expect(native().initialize).toHaveBeenCalledTimes(1);

    await expect(
      OmnixVoice.initialize(sampleConfig({ sipUser: 'other@example.com' })),
    ).rejects.toMatchObject({ code: 'INVALID_CALL_STATE' });
  });

  it('caches registration and call state from events and allows listener removal', async () => {
    await OmnixVoice.initialize(sampleConfig());
    const seen: string[] = [];
    const listener = (state: string): void => {
      seen.push(state);
    };
    OmnixVoice.addListener('registrationStateChanged', listener);

    emit('omnixRegistrationStateChanged', {
      state: 'REGISTERED',
      sipCode: 200,
      reason: 'ok',
    });
    expect(OmnixVoice.getRegistrationState()).toBe('REGISTERED');
    expect(seen).toEqual(['REGISTERED']);

    OmnixVoice.removeListener('registrationStateChanged', listener);
    emit('omnixRegistrationStateChanged', { state: 'REGISTERING' });
    expect(seen).toEqual(['REGISTERED']);
    expect(OmnixVoice.getRegistrationState()).toBe('REGISTERING');

    emit('omnixRegistrationStateChanged', { state: 'REGISTERED' });
    expect(OmnixVoice.getRegistrationState()).toBe('REGISTERED');

    const call: OmnixCallInfo = {
      callId: 'call-1',
      peerUri: 'sip:peer@example.com',
      peerDisplayName: 'Peer',
      state: 'INCOMING',
      isOutgoing: false,
      isMuted: false,
      isOnHold: false,
    };
    emit('omnixIncomingCall', call);
    expect(OmnixVoice.getCallInfo('call-1')).toEqual(call);

    const callId = await OmnixVoice.makeCall('sip:peer@example.com');
    expect(callId).toBe('call-1');
    expect(native().makeCall).toHaveBeenCalledWith('sip:peer@example.com');
  });

  it('rejects makeCall before registration and maps native error codes', async () => {
    await OmnixVoice.initialize(sampleConfig());
    await expect(OmnixVoice.makeCall('sip:peer@example.com')).rejects.toMatchObject(
      { code: 'NOT_REGISTERED' },
    );
    expect(native().makeCall).not.toHaveBeenCalled();

    emit('omnixRegistrationStateChanged', { state: 'REGISTERED' });
    native().makeCall.mockRejectedValueOnce({
      code: 'CALL_BUSY',
      message: 'busy',
    });
    await expect(OmnixVoice.makeCall('sip:peer@example.com')).rejects.toMatchObject(
      { code: 'CALL_BUSY' },
    );
  });

  it('rejects blind transfer with NOT_SUPPORTED and never calls native', async () => {
    await expect(
      OmnixVoice.transferCall('call-1', 'sip:other@example.com'),
    ).rejects.toMatchObject({ code: 'NOT_SUPPORTED' });
    expect(native().transferCall).not.toHaveBeenCalled();
    expect(consoleText()).not.toContain(SECRET);
  });

  it('drops native subscriptions on shutdown', async () => {
    await OmnixVoice.initialize(sampleConfig());
    expect(native().addListener).toHaveBeenCalledTimes(5);
    await OmnixVoice.shutdown();
    expect(native().removeListeners).toHaveBeenCalledTimes(5);
    expect(native().shutdown).toHaveBeenCalledTimes(1);
    expect(OmnixVoice.getRegistrationState()).toBe('UNINITIALIZED');
  });

  it('redacts credential-shaped text in error events', async () => {
    await OmnixVoice.initialize(sampleConfig());
    const errors: OmnixVoiceError[] = [];
    OmnixVoice.addListener('error', (err) => {
      errors.push(err);
    });
    emit('omnixError', {
      code: 'AUTHENTICATION_FAILED',
      detail: `password=${SECRET}`,
      callId: 'call-9',
    });
    expect(errors).toHaveLength(1);
    expect(errors[0]?.code).toBe('AUTHENTICATION_FAILED');
    expect(errors[0]?.detail).toBe('password=[REDACTED]');
    expect(errors[0]?.callId).toBe('call-9');
    expect(errors[0]?.message).not.toContain(SECRET);
    expect(consoleText()).not.toContain(SECRET);
  });

  it('rejects calls before initialize and validates arguments', async () => {
    await expect(OmnixVoice.register()).rejects.toMatchObject({
      code: 'INVALID_CALL_STATE',
    });
    await expect(OmnixVoice.makeCall('   ')).rejects.toMatchObject({
      code: 'INVALID_CALL_STATE',
    });
    await expect(
      OmnixVoice.transferCall('  ', 'sip:other@example.com'),
    ).rejects.toMatchObject({ code: 'INVALID_CONFIGURATION' });
    expect(OmnixVoice.getCallInfo('missing')).toBeNull();
    await OmnixVoice.shutdown();
    expect(native().shutdown).not.toHaveBeenCalled();
  });

  it('forwards call controls and DTMF after registration', async () => {
    await OmnixVoice.initialize(
      sampleConfig({
        authUser: 'auth-user',
        displayName: 'Display',
        stunServer: 'stun.example.com',
        verifyCert: false,
        enableSrtp: false,
        codecs: ['pcmu', 'pcma', 'opus'],
      }),
    );
    await OmnixVoice.register();
    emit('omnixRegistrationStateChanged', { state: 'REGISTERED' });
    await OmnixVoice.answerCall('call-1');
    await OmnixVoice.rejectCall('call-1');
    await OmnixVoice.hangupCall('call-1');
    await OmnixVoice.holdCall('call-1');
    await OmnixVoice.resumeCall('call-1');
    await OmnixVoice.setMuted('call-1', true);
    await OmnixVoice.setSpeakerEnabled(true);
    await OmnixVoice.sendDTMF('call-1', 'a');
    await OmnixVoice.unregister();

    expect(native().register).toHaveBeenCalled();
    expect(native().answerCall).toHaveBeenCalledWith('call-1');
    expect(native().rejectCall).toHaveBeenCalledWith('call-1');
    expect(native().hangupCall).toHaveBeenCalledWith('call-1');
    expect(native().holdCall).toHaveBeenCalledWith('call-1');
    expect(native().resumeCall).toHaveBeenCalledWith('call-1');
    expect(native().setMuted).toHaveBeenCalledWith('call-1', true);
    expect(native().setSpeakerEnabled).toHaveBeenCalledWith(true);
    expect(native().sendDTMF).toHaveBeenCalledWith('call-1', 'A');
    expect(native().unregister).toHaveBeenCalled();
    expect(native().initialize).toHaveBeenCalledWith(
      expect.objectContaining({
        authUser: 'auth-user',
        verifyCert: false,
        enableSrtp: false,
        codecs: 'pcmu,pcma,opus',
      }),
    );
  });

  it('rejects invalid DTMF, blank call ids, and a failed makeCall', async () => {
    await OmnixVoice.initialize(sampleConfig());
    emit('omnixRegistrationStateChanged', { state: 'REGISTERED' });
    await expect(OmnixVoice.sendDTMF('call-1', '12')).rejects.toMatchObject({
      code: 'INVALID_CONFIGURATION',
    });
    await expect(OmnixVoice.answerCall('  ')).rejects.toMatchObject({
      code: 'INVALID_CONFIGURATION',
    });
    await expect(OmnixVoice.makeCall('  ')).rejects.toMatchObject({
      code: 'INVALID_CONFIGURATION',
    });
    native().makeCall.mockResolvedValueOnce('');
    await expect(OmnixVoice.makeCall('sip:peer@example.com')).rejects.toMatchObject(
      { code: 'CALL_FAILED' },
    );
  });

  it('keeps delivering events when one listener throws and ignores invalid payloads', async () => {
    await OmnixVoice.initialize(sampleConfig());
    const seen: string[] = [];
    OmnixVoice.addListener('audioRouteChanged', () => {
      throw new Error('host listener failed');
    });
    OmnixVoice.addListener('audioRouteChanged', (route) => {
      seen.push(route);
    });
    emit('omnixAudioRouteChanged', { route: 'SPEAKER' });
    emit('omnixAudioRouteChanged', { route: 'NOT_A_ROUTE' });
    emit('omnixCallStateChanged', { callId: '' });
    const errors: string[] = [];
    OmnixVoice.addListener('error', (err) => {
      errors.push(err.code);
    });
    emit('omnixIncomingCall', { nope: true });
    expect(seen).toEqual(['SPEAKER']);
    expect(errors).toContain('INTERNAL_NATIVE_ERROR');

    emit('omnixCallStateChanged', {
      callId: 'call-2',
      peerUri: 'sip:peer@example.com',
      state: 'CONNECTED',
      isOutgoing: true,
      isMuted: false,
      isOnHold: false,
      durationSeconds: 3,
    });
    expect(OmnixVoice.getCallInfo('call-2')?.state).toBe('CONNECTED');
    expect(OmnixVoice.getCallInfo('call-2')?.durationSeconds).toBe(3);
  });

  it('rejects an empty codec list before calling native', async () => {
    await expect(
      OmnixVoice.initialize(sampleConfig({ codecs: [] })),
    ).rejects.toMatchObject({ code: 'INVALID_CONFIGURATION' });
    expect(native().initialize).not.toHaveBeenCalled();
  });
});
