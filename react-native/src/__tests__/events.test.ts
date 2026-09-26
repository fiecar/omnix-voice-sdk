import {
  parseAudioRoute,
  parseCallInfo,
  parseErrorEvent,
  parseRegistrationEvent,
} from '../events';

const call = {
  callId: 'call-1',
  peerUri: 'sip:peer@example.com',
  state: 'RINGING',
  isOutgoing: false,
  isMuted: true,
  isOnHold: false,
};

describe('native event parsers', () => {
  it('parses registration payloads and rejects malformed ones', () => {
    expect(parseRegistrationEvent(null)).toBeNull();
    expect(parseRegistrationEvent({ state: 'NOPE' })).toBeNull();
    expect(parseRegistrationEvent({ state: 'REGISTERED', sipCode: '200' })).toBeNull();
    expect(
      parseRegistrationEvent({ state: 'REGISTERED', reason: 12 }),
    ).toBeNull();
    expect(
      parseRegistrationEvent({
        state: 'REGISTERED',
        sipCode: 200,
        reason: 'ok',
      }),
    ).toEqual({ state: 'REGISTERED', sipCode: 200, reason: 'ok' });
    expect(
      parseRegistrationEvent({ state: 'REGISTERING', sipCode: null, reason: null }),
    ).toEqual({ state: 'REGISTERING' });
  });

  it('parses call info and audio routes', () => {
    expect(parseCallInfo(null)).toBeNull();
    expect(parseCallInfo({ ...call, callId: '' })).toBeNull();
    expect(parseCallInfo({ ...call, peerUri: 1 })).toBeNull();
    expect(parseCallInfo({ ...call, state: 'NOPE' })).toBeNull();
    expect(parseCallInfo({ ...call, isMuted: 'yes' })).toBeNull();
    expect(parseCallInfo(call)).toMatchObject({ callId: 'call-1', state: 'RINGING' });
    expect(
      parseCallInfo({
        ...call,
        peerDisplayName: 'Ada',
        durationSeconds: 4,
      })?.durationSeconds,
    ).toBe(4);
    expect(parseCallInfo({ ...call, durationSeconds: Number.NaN })?.durationSeconds).toBeUndefined();

    expect(parseAudioRoute({ route: 'BLUETOOTH' })).toBe('BLUETOOTH');
    expect(parseAudioRoute({ route: 'NOPE' })).toBeNull();
    expect(parseAudioRoute(null)).toBeNull();
  });

  it('parses error events and drops unknown codes', () => {
    expect(parseErrorEvent(null)).toBeNull();
    expect(parseErrorEvent({ code: 1 })).toBeNull();
    expect(parseErrorEvent({ code: 'NOPE' })).toBeNull();
    const parsed = parseErrorEvent({
      code: 'CALL_REJECTED',
      detail: 'busy',
      callId: 'call-3',
    });
    expect(parsed?.code).toBe('CALL_REJECTED');
    expect(parsed?.callId).toBe('call-3');
    expect(parseErrorEvent({ code: 'TIMEOUT', detail: 1 })?.detail).toBeUndefined();
  });
});
