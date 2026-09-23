# NAT traversal — Phase 2 (POST-MVP)

**Status:** Assessment only (SDK-028 / frozen F-8). Not implemented in MVP.

## MVP (DONE in SDK-028)

- Optional `omnix_config_t.stun_server` / `stunServer` wires to Baresip
  `account_set_medianat("stun")` + `account_set_stun_uri()`.
- Static module list includes `stun`.
- `turn:` / `turns:` URIs are rejected with `OMNIX_ERR_NOT_SUPPORTED`.
- Live STUN validation against a real SBC/PBX may be postponed when the
  environment fully handles NAT; report as KNOWN LIMITATIONS (gate H-3).

## POST-MVP — TURN

- Vendored Baresip already has a `turn` module; Omnix must **not** enable it
  for MVP.
- Would require: credentialed TURN URI, secure storage of TURN secrets
  (same wipe/redact rules as SIP password), and CI/secrets via gate H-3 only.
- Open a Phase 2 issue before enabling `account_set_stun_uri` with `turn:` /
  `turns:` schemes or loading the `turn` module.

## POST-MVP — full ICE

- Baresip `ice` module + `account_set_medianat(acc, "ice")` is a separate
  media-NAT path from simple STUN keepalive.
- Full ICE needs candidate gathering, consent freshness, and careful
  interaction with `dtls_srtp` — out of MVP scope.
- Do not set medianat to `ice` until a Phase 2 design is approved in Issue #1.

## Executor guardrails

- Do not upgrade Baresip/re to “get better ICE”.
- Do not invent public API names for TURN/ICE; extend Issue #1 §20A first.
