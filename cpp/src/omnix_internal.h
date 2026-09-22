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

struct omnix_state {
	bool initialized;
	bool re_thread_started;
	omnix_reg_state_t reg_state;
	omnix_config_t config; /* callbacks + non-secret config (no password) */
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

/* Subsystems */
omnix_error_t omnix_account_setup(const omnix_config_t *config);
void omnix_account_teardown(void);
omnix_error_t omnix_events_init(void);
void omnix_events_shutdown(void);
int omnix_events_request_ready_signal(void);
int omnix_events_request_shutdown(void);

/* Lifecycle helpers (SDK-011) — signal that re_main is polling */
void omnix_lifecycle_on_re_ready(void);

#ifdef __cplusplus
}
#endif

#endif /* OMNIX_INTERNAL_H */
