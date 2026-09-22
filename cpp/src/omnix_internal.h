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
	omnix_reg_state_t reg_state;
	omnix_config_t config; /* callback pointers + non-secret config copies */
	char *password_for_filter; /* Omnix-owned copy used only for log redaction */
	void *mqueue; /* opaque: struct mqueue* when wired (SDK-011+) */
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

/* Subsystem stubs (filled in later tasks) */
omnix_error_t omnix_account_setup(const omnix_config_t *config);
void omnix_account_teardown(void);
omnix_error_t omnix_events_init(void);
void omnix_events_shutdown(void);

#ifdef __cplusplus
}
#endif

#endif /* OMNIX_INTERNAL_H */
