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
});
