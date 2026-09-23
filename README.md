# Omnix Voice SDK

Reusable enterprise VoIP SDK for React Native (Android + iOS).

Wraps the open-source Baresip SIP stack behind an Omnix-branded public API.
Client applications never touch Baresip internals.

## Architecture

Architecture decisions, frozen public API, upstream baseline, and security
requirements are defined in:

- [Issue #1 — Architecture](https://github.com/fiecar/omnix-voice-sdk/issues/1)
- [Issue #2 — Detailed implementation plan](https://github.com/fiecar/omnix-voice-sdk/issues/2)

## Status

Repository bootstrap in progress. Native core, Android, iOS, and React Native
packages will land in subsequent `SDK-XXX` tasks.

## Android integration

See [docs/integration-android.md](docs/integration-android.md) for host-app
permissions (`RECORD_AUDIO` runtime request before `initialize()`), credentials,
and MVP incoming-call limits.

## License

Omnix Voice SDK source (outside `third_party/`) — see repository license when published.
Third-party components retain their original licenses; see `THIRD_PARTY_NOTICES.md`
and `LICENSES/` after upstream import.
