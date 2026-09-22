# AGENTS.md — Omnix Voice SDK

Instructions for AI coding agents and junior developers working in this repository.

## Architecture source of truth

- **Architecture (frozen):** [Issue #1](https://github.com/fiecar/omnix-voice-sdk/issues/1) — decisions F-1…F-18, public API §20A, upstream baseline, security, credentials §26.
- **Implementation plan:** [Issue #2](https://github.com/fiecar/omnix-voice-sdk/issues/2) — task definitions SDK-001…SDK-067, executor rules, human gates.

Do **not** redesign architecture. Do **not** invent public API names. Escalate conflicts to the Issue #1 author / lead; report status `BLOCKED`.

---

## Commit and branch conventions

| Item | Rule |
|------|------|
| Commit message | `[SDK-XXX] short description` (one task per commit) |
| Feature branch | `feature/sdk-XXX-short-desc` (example: `feature/sdk-002-agents-md`) |
| Target | PR into `main`; lead merges |
| Direct `main` | Forbidden from **SDK-002 onward**. (SDK-001 bootstrap may commit to `main`.) |

---

## Language standards

| Layer | Standard |
|-------|----------|
| Native C facade (`cpp/`) | **C11** |
| Android public / internal API | **Kotlin** (package `com.omnix.voice`) |
| iOS public API | **Swift 5.9+** |
| iOS bridge | Objective-C / Objective-C++ as required by the bridge layer |
| React Native package | **TypeScript strict** (`strict: true` in `tsconfig.json`) |

Do not silence compiler warnings without documenting why. Do not disable TLS certificate verification (default must remain `true`).

---

## 🛑 RULES FOR CURSOR AUTO / JUNIOR EXECUTOR

1. **Execute EXACTLY ONE `SDK-XXX` task at a time.**
2. **Do NOT automatically continue to the next task.**
3. **After completing a task:**
 - run ALL verification specified in the task;
 - run tests;
 - inspect `git diff` (and `git status`);
 - confirm no secrets (no passwords, tokens, real hostnames/IPs, customer data);
 - confirm no unintended `third_party/` changes (`scripts/verify-third-party.ps1` / `.sh` once it exists);
 - commit **only that task**;
 - report the result using the **Task Report** format below;
 - **STOP.**
4. **A human / lead agent starts the next task.**
5. **If the task uncovers an architecture conflict: STOP. Do not redesign. Report the conflict** (status `BLOCKED`).
6. **Never upgrade Baresip, re, OpenSSL, libopus, NDK, AGP, Gradle, React Native or any other foundational dependency ad hoc.**
7. **Never modify `third_party/` unless the active task specifically requires an approved patch** (recorded in `PATCHES.md`). Import tasks (SDK-003/004/066/067) write `third_party/` only through the import script.
8. **Never mark a GitHub checkbox complete merely because code was written. Verification must actually pass.**
9. **Do not push directly to `main` once branch workflow is active.** Branch workflow is active from **SDK-002 onward**: branch `feature/sdk-XXX-short-desc`, PR into `main`, lead merges. (SDK-001 may be committed directly to `main` because the repository is being bootstrapped.)
10. **Do not combine unrelated SDK tasks into one commit.** Commit format: `[SDK-XXX] short description`.

### Task status protocol

Each task has exactly one status: **`NOT STARTED`** · **`IN PROGRESS`** · **`BLOCKED`** · **`DONE`**.
`DONE` = all acceptance criteria verified and the lead has accepted the report. `BLOCKED` = stopped with a reported reason; only the lead unblocks.

### Task Report (mandatory final output of every task — post as a comment on this issue)

```
TASK:
STATUS:                 (NOT STARTED | IN PROGRESS | BLOCKED | DONE)
BRANCH:
COMMIT:
FILES CHANGED:
TESTS RUN:
TEST RESULTS:
SECURITY CHECK:         (secrets scan / credential-in-log check result)
LICENSE CHECK:          (license scan result; third_party unchanged? yes/no)
KNOWN LIMITATIONS:
NEXT RECOMMENDED TASK:
```

> ⚠️ Auto MUST NOT start the NEXT RECOMMENDED TASK automatically. It is a recommendation for the lead only.

### Human gates (the executor STOPS and waits at these points)

| Gate | Before task | Decision |
|------|-------------|----------|
| **H-1** | SDK-046 (and DEMO-001) | Lead pins the exact React Native version + matching AGP/Gradle; records in `docs/toolchain.md`. |
| **H-2** | SDK-030 merge | Lead approves exact NDK (≥ r28) and AGP (≥ 8.9.1) versions pinned in the PR. |
| **H-3** | SDK-013 real-server verification, SDK-053, SDK-065 | Lead provides test SIP environment via env vars / CI secrets only (never in issues or committed files). |

### ⚠️ MVP incoming-call limitation (do NOT treat background telephony as MVP)

MVP incoming-call support = incoming calls **while the app process is alive, the SDK is initialized/registered, and the app is in the foreground lifecycle**. The MVP does NOT support, and no task may require, incoming calls when the Android process is killed, the iOS app is terminated, the OS suspends the app, or wake-up requires PushKit/FCM. Foreground service, ConnectionService, FCM, CallKit, PushKit, APNs and killed-app support are **Phase 2** (SDK-035, SDK-044, SDK-045 are documentation-only POST-MVP tasks). See Issue #1 §0.1.

### Windows command conventions

- Primary workspace is Windows (a local folder containing `omnix-voice-sdk\` and `omnix-voice-demo\` side by side). Commands shown with `powershell` fences run directly in PowerShell.
- `.ps1` scripts target **PowerShell 7** (`pwsh`; install with `winget install Microsoft.PowerShell`). Windows 10+ built-ins used: `tar.exe`, `Get-FileHash`, `git`.
- Gradle: `.\gradlew.bat ` on Windows; `./gradlew ` on Linux/macOS CI.
- Every important verification script has a `.ps1` (Windows) and a `.sh` (Linux CI) variant with identical pass/fail semantics: `verify-abi`, `verify-16kb-alignment`, `check-licenses`, `check-api-leakage`, `verify-third-party`, `import-upstream`, `generate-checksums`, `generate-sbom`.
- Anything that genuinely needs a POSIX shell is marked **[BASH/WSL/GIT-BASH REQUIRED]** (or **[BASH/WSL REQUIRED]** when Git Bash is not enough, e.g. OpenSSL needs `make` + `perl`). Do NOT install WSL for tasks that are not marked.
- iOS work is **[MACOS REQUIRED]**.
- The workspace path may contain spaces (e.g. OneDrive folders): always quote paths in scripts. Never write local absolute paths or usernames into committed files.

---

## Additional executor guardrails

These mirror Issue #2 “ADDITIONAL EXECUTOR RULES” and remain binding:

1. Work on **ONE** task at a time. Commit before moving to the next.
2. Read **Dependencies** before starting. Do not skip them.
3. Do **NOT** redesign the architecture. Escalate to Issue #1 author if needed.
4. Do **NOT** update Baresip / re versions. Approved: Baresip `v4.11.0` @ `3d30821f099925d24167f8a99e93ba4d1be98599`; re `v4.11.0` @ `ceefe9ff499aa1bcfb6255aff1737434dd385322`.
5. Do **NOT** rename or modify files in `third_party/` except via approved patches in `PATCHES.md` / import scripts.
6. Do **NOT** remove copyright/license headers from `third_party/` files.
7. Do **NOT** add dependencies without posting a comment on Issue #2 first (reason, version, license).
8. Do **NOT** commit credentials, passwords, IPs, or production domains.
9. Do **NOT** disable TLS cert validation. Default must be `true`.
10. Do **NOT** silence compiler warnings without documenting why.
11. Do **NOT** check acceptance boxes without actually running the verification.
12. Keep commits atomic. Format: `[SDK-XXX] short description`.
13. Add/update tests alongside implementation.
14. If blocked: **STOP**. Post: task ID, command used, exact error, log, what you tried (redact hostnames/credentials).
15. Do **NOT** invent public API names. Use exactly Issue #1 §20A. Public API changes after SDK-011 require a documented reason, an Issue #1 update, and an API compatibility review.
16. No Baresip/re type may cross the Omnix facade (Kotlin, Swift, ObjC, TypeScript, public C headers). `struct ua*`, `struct call*`, `struct account*` etc. stay inside `cpp/src/`.
17. Never download sources from `main`/`master` or a floating branch; release builds download no native sources at all.
18. Use placeholders only (`sip.example.com`, `user@example.com`) in code, docs, tests, issues and comments.

---

## ABI / API leakage rule

Acceptance criterion for every public-surface task (Issue #1 §12):

- **No Baresip or re type may appear in:** the Kotlin public API, the Swift public API, the Objective-C public headers, the TypeScript public API, or the public C facade headers (`omnix_voice.h`, `omnix_types.h`).
- Forbidden across the Omnix facade boundary (non-exhaustive): `struct ua*`, `struct call*`, `struct account*`, `struct config*`, `struct mqueue*`, `struct sa`, `struct pl`, `struct mbuf`, any `enum ua_event` / `enum call_event` / `enum call_state` / `enum vidmode` / `enum sdp_dir`, any `re_*` / `mem_*` handle, any Baresip integer error code (`errno`-style values).
- Public headers MUST NOT `#include` `baresip.h`, `re.h` or any file under `third_party/`.
- The C facade MAY own these handles **internally** (e.g. in `cpp/src/`), never in a public header.
- Enforced by `scripts/check-api-leakage.(sh|ps1)` (SDK-010; CI in SDK-057).

---

## Credential rules (Issue #1 §26)

**Ownership model (frozen — F-17):** The SDK may **receive** SIP credentials from the host application at runtime. The SDK does **NOT** persist them by default. Long-term credential storage is the **host application's** responsibility, unless a future secure-credential feature is explicitly approved (Phase 2+).

The SDK MUST NOT:

- write SIP passwords to logs (any level, any build type — native, Kotlin, Swift, JS);
- persist the password in plain text (no `SharedPreferences`, files, `NSUserDefaults`, AsyncStorage, SQLite, Baresip config files on disk);
- include credentials in exception messages, error `detail` strings, crash messages or native abort messages;
- place credentials in React Native debug output (event payloads, `console.*`, Flipper/DevTools logs, `toString()` / `JSON.stringify` of config — config serialization redacts `sipPassword`);
- echo the password back in any event or `OmnixCallInfo`.

Implementation rules:

- The C facade copies `sip_password` into an Omnix-owned buffer, passes it to Baresip auth APIs, then zeroes its own copy with a non-optimizable wipe. It MUST NOT write into caller-owned memory.
- The AOR string MUST NOT contain the password (no `;auth_pass=`), because AORs are loggable.
- SIP passwords are **never committed to source code**.
- No credential in any GitHub Issue, PR description, comment, or CI log. CI uses GitHub Secrets (masked).
- Public text uses placeholders only: `sip.example.com`, `user@example.com`, `stun.example.com`.

Sensitive fields to redact in logs: `sip_password`, `auth_pass`, any field named `token`, `secret`, `credential`, `cert`.

---

## Upstream and licensing reminders

- Preserve upstream `LICENSE` / copyright / attribution / provenance.
- Record approved `third_party/` patches only in `PATCHES.md`.
- See `UPSTREAM.md` and `THIRD_PARTY_NOTICES.md` after import tasks.
- Never mass-rename Baresip / re source under `third_party/`.
