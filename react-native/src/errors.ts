/**
 * Omnix-owned errors (Issue #1 §20A.6).
 * Raw native status numbers are mapped before they reach this type.
 */
import type { OmnixErrorCode } from './types';

/** Keys must be the complete OmnixErrorCode union (missing or extra codes fail tsc). */
const ERROR_CODE_COVERAGE = {
  INITIALIZATION_ERROR: true,
  INVALID_CONFIGURATION: true,
  REGISTRATION_FAILED: true,
  AUTHENTICATION_FAILED: true,
  NETWORK_UNAVAILABLE: true,
  TLS_ERROR: true,
  MEDIA_ERROR: true,
  CALL_FAILED: true,
  CALL_BUSY: true,
  CALL_REJECTED: true,
  TIMEOUT: true,
  NOT_REGISTERED: true,
  INVALID_CALL_STATE: true,
  PERMISSION_DENIED: true,
  TRANSFER_FAILED: true,
  NOT_SUPPORTED: true,
  INTERNAL_NATIVE_ERROR: true,
} as const satisfies Record<OmnixErrorCode, true>;

const ERROR_CODE_SET: ReadonlySet<string> = new Set(
  Object.keys(ERROR_CODE_COVERAGE),
);

export function isOmnixErrorCode(value: string): value is OmnixErrorCode {
  return ERROR_CODE_SET.has(value);
}

function buildMessage(code: OmnixErrorCode, detail?: string): string {
  if (detail == null || detail.trim() === '') {
    return `OmnixVoice error: ${code}`;
  }
  return `OmnixVoice error: ${code} — ${detail}`;
}

/**
 * Synchronous and event failures.
 * `callId` carries the §20A.5 error-event field when the native payload had one.
 * `detail` must never contain a SIP password.
 */
export class OmnixVoiceError extends Error {
  readonly code: OmnixErrorCode;
  readonly detail?: string;
  readonly callId?: string;

  constructor(code: OmnixErrorCode, detail?: string, callId?: string) {
    super(buildMessage(code, detail));
    this.name = 'OmnixVoiceError';
    this.code = code;
    this.detail = detail;
    this.callId = callId;
    Object.setPrototypeOf(this, new.target.prototype);
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

/**
 * Replace credential material in untrusted native text.
 * `secret` is only available while `initialize()` is still on the stack.
 */
export function scrubDetail(
  detail: string | undefined,
  secret?: string,
): string | undefined {
  if (detail == null || detail === '') {
    return undefined;
  }
  let out = detail;
  if (secret != null && secret.length > 0 && out.includes(secret)) {
    out = out.split(secret).join('[REDACTED]');
  }
  out = out.replace(
    /((?:sipPassword|auth_pass|password)\s*[:=]\s*)(\S+)/gi,
    '$1[REDACTED]',
  );
  if (out.length > 180) {
    out = out.slice(0, 180);
  }
  return out;
}

/** Map an untrusted native rejection to an Omnix error. */
export function toOmnixError(
  error: unknown,
  secret?: string,
): OmnixVoiceError {
  if (error instanceof OmnixVoiceError) {
    return error;
  }

  let code: OmnixErrorCode = 'INTERNAL_NATIVE_ERROR';
  let detail: string | undefined;
  let callId: string | undefined;

  if (isRecord(error)) {
    if (typeof error.code === 'string' && isOmnixErrorCode(error.code)) {
      code = error.code;
    }
    if (typeof error.detail === 'string') {
      detail = error.detail;
    } else if (typeof error.message === 'string') {
      detail = error.message;
    }
    if (typeof error.callId === 'string' && error.callId.length > 0) {
      callId = error.callId;
    }
  } else if (typeof error === 'string' && isOmnixErrorCode(error)) {
    code = error;
  } else if (error instanceof Error) {
    detail = error.message;
  }

  return new OmnixVoiceError(code, scrubDetail(detail, secret), callId);
}
