/**
 * Omnix Voice — internal shared state (NOT public).
 * May include Baresip / re types. Never install or expose this header.
 */
#ifndef OMNIX_INTERNAL_H
#define OMNIX_INTERNAL_H

#include "omnix_voice/omnix_types.h"

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Forward decls — Baresip types stay out of public headers. */
struct ua;
struct call;

/* SDK-015: internal call registry entry (struct call * never public). */
typedef struct omnix_call_entry {
	char call_id[128];
	struct call *baresip_call; /* NEVER exposed publicly */
	omnix_call_info_t info;
} omnix_call_entry_t;

struct omnix_state {
	bool initialized;
	bool re_thread_started;
	bool unregister_pending; /* expire=0 REGISTER_OK → UNREGISTERED */
	bool shutting_down; /* skip mqueue reg notify during teardown */
	omnix_reg_state_t reg_state;
	omnix_config_t config; /* callbacks + non-secret config (no password) */
	struct ua *ua; /* SDK-012; never exposed publicly */
	char aor_built[512]; /* Omnix-built AOR (no password); for tests */
	/* Fingerprint strings for idempotent omnix_init (owned, heap). */
	char *fp_sip_server;
	char *fp_sip_user;
	char *fp_auth_user;
	char *fp_display_name;
	char *fp_stun_server;
	char *fp_audio_module;
	char *fp_codecs;
	char *password_for_filter; /* Omnix-owned copy used only for log redaction */
	void *mqueue; /* opaque: struct mqueue* */
	/* SDK-021: speaker preference (platform applies route in SDK-034/042). */
	bool speaker_enabled;
};

struct omnix_state *omnix_state_get(void);

/* Password helpers — Omnix-owned buffers only */
char *omnix_password_dup(const char *src);
void omnix_password_wipe_free(char *pw);

/* Log redaction (Baresip log handler path) */
void omnix_log_filter_set_secret(const char *secret);
void omnix_log_filter_clear(void);
int omnix_log_redact_to(const char *msg, char *out, size_t out_len);
void omnix_log_handler_register(void);
void omnix_log_handler_unregister(void);

/* Test helpers (used by tests/native) */
void omnix_test_reset_last_log(void);
const char *omnix_test_last_log(void);
void omnix_test_emit_via_log_path(const char *msg);
const char *omnix_test_account_aor(void);
const char *omnix_test_account_aor_built(void);
int omnix_test_account_has_tls_transport(void);
const char *omnix_test_account_mediaenc(void);
const char *omnix_test_account_auth_user(void);
const char *omnix_test_account_display_name(void);
const char *omnix_test_account_outbound(void);
/* kind: 0=REGISTER_OK, 1=REGISTER_FAIL, 2=UNREGISTERING, 3=REGISTERING */
int omnix_test_inject_reg_bevent(int kind, const char *text);

/* SDK-015 call registry */
void omnix_call_registry_reset(void);
omnix_call_entry_t *omnix_find_call_by_id(const char *call_id);
omnix_call_entry_t *omnix_find_call_by_ptr(const struct call *call);
omnix_call_entry_t *omnix_alloc_call_slot(struct call *call);
void omnix_free_call_slot(omnix_call_entry_t *entry);
void omnix_call_info_from_baresip(omnix_call_info_t *info, struct call *call);
unsigned omnix_call_registry_count(void);
unsigned omnix_call_registry_capacity(void);
/* Test: install synthetic slot (fake ptr) for capacity / find helpers. */
omnix_call_entry_t *omnix_test_install_call_slot(const char *call_id,
						 struct call *fake_ptr);
/* Test: ua_call_alloc + call_connect (invite may fail); sets id/peer. */
int omnix_test_make_baresip_outgoing_call(struct call **callp,
					  const char *peer_uri);
void omnix_test_release_baresip_call(struct call *call);
/* Test/SDK-017: emit BEVENT_CALL_INCOMING for a allocated call (no INVITE). */
int omnix_test_inject_incoming_bevent(const char *peer_uri);
/* Test/SDK-019: simulate CALL_EVENT_CLOSED (optional SIP text → FAILED). */
int omnix_test_inject_call_closed(const char *call_id, const char *str);
/* Test/SDK-020: allocate audio streams if lazy path never ran (host inject). */
int omnix_test_ensure_call_audio(const char *call_id);
/* Test/SDK-020: audio local SDP dir after mute (0=INACTIVE…3=SENDRECV), -1 err. */
int omnix_test_call_audio_ldir(const char *call_id);
/* Test/SDK-021: stored speaker preference (0/1); -1 if not initialized. */
int omnix_test_speaker_enabled(void);
/* Test/SDK-022: last digit accepted by omnix_call_send_dtmf; 0 if none. */
char omnix_test_last_dtmf_digit(void);
void omnix_test_reset_last_dtmf(void);
/* Test/SDK-023: set Omnix entry state CONNECTED (host never ESTABLISHED). */
int omnix_test_force_call_connected(const char *call_id);
/* Test/SDK-023: Baresip call_is_onhold (1/0); -1 if call missing. */
int omnix_test_call_is_onhold(const char *call_id);

/* SDK-017: handle BEVENT_CALL_INCOMING under re lock (mqueue for app cb). */
void omnix_call_handle_incoming(struct call *call);

/* Subsystems */
omnix_error_t omnix_account_setup(const omnix_config_t *config);
void omnix_account_teardown(void);
void omnix_account_unload_modules(void);
omnix_error_t omnix_events_init(void);
void omnix_events_shutdown(void);
int omnix_events_request_ready_signal(void);
int omnix_events_request_shutdown(void);
int omnix_events_notify_registering(void);
int omnix_events_notify_reg_state(omnix_reg_state_t state, int sip_code,
				  const char *reason);
/* SDK-016: enqueue on_call_event (outside re lock via mqueue). */
int omnix_events_notify_call_state(omnix_call_state_t state,
				   const omnix_call_info_t *info);

/* Lifecycle helpers (SDK-011) — signal that re_main is polling */
void omnix_lifecycle_on_re_ready(void);

#ifdef __cplusplus
}
#endif

#endif /* OMNIX_INTERNAL_H */
