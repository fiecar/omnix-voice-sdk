import { OmnixVoiceError, isOmnixErrorCode, scrubDetail, toOmnixError } from '../errors';

describe('Omnix error mapping', () => {
  it('accepts only canonical codes', () => {
    expect(isOmnixErrorCode('TLS_ERROR')).toBe(true);
    expect(isOmnixErrorCode('NOT_A_CODE')).toBe(false);
  });

  it('builds messages with and without detail', () => {
    expect(new OmnixVoiceError('TIMEOUT').message).toBe(
      'OmnixVoice error: TIMEOUT',
    );
    expect(new OmnixVoiceError('TIMEOUT', '   ').message).toBe(
      'OmnixVoice error: TIMEOUT',
    );
    expect(new OmnixVoiceError('CALL_BUSY', 'busy', 'call-1').callId).toBe(
      'call-1',
    );
  });

  it('maps native rejections without copying a password', () => {
    const existing = new OmnixVoiceError('MEDIA_ERROR', 'route');
    expect(toOmnixError(existing)).toBe(existing);

    const fromDetail = toOmnixError({
      code: 'TLS_ERROR',
      detail: 'password=hunter2',
      callId: 'call-4',
    });
    expect(fromDetail.code).toBe('TLS_ERROR');
    expect(fromDetail.detail).toBe('password=[REDACTED]');
    expect(fromDetail.callId).toBe('call-4');

    const fromMessage = toOmnixError(
      { code: 'NOT_A_CODE', message: 'secret-value failed' },
      'secret-value',
    );
    expect(fromMessage.code).toBe('INTERNAL_NATIVE_ERROR');
    expect(fromMessage.message).not.toContain('secret-value');

    expect(toOmnixError('NETWORK_UNAVAILABLE').code).toBe('NETWORK_UNAVAILABLE');
    expect(toOmnixError(new Error('boom')).detail).toBe('boom');
    expect(toOmnixError(12).code).toBe('INTERNAL_NATIVE_ERROR');
    expect(scrubDetail(undefined)).toBeUndefined();
    expect(scrubDetail('')).toBeUndefined();
    expect((scrubDetail('x'.repeat(200)) ?? '').length).toBe(180);
  });
});
