/**
 * Omnix Voice SDK — public C types (Issue #1 §20A).
 * Baresip / re types MUST NOT appear in this header.
 */
#ifndef OMNIX_VOICE_OMNIX_TYPES_H
#define OMNIX_VOICE_OMNIX_TYPES_H

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    OMNIX_REG_UNINITIALIZED = 0,
    OMNIX_REG_UNREGISTERED,
    OMNIX_REG_REGISTERING,
    OMNIX_REG_REGISTERED,
    OMNIX_REG_FAILED,
} omnix_reg_state_t;

typedef enum {
    OMNIX_CALL_IDLE = 0,
    OMNIX_CALL_OUTGOING,
    OMNIX_CALL_INCOMING,
    OMNIX_CALL_RINGING,
    OMNIX_CALL_EARLY_MEDIA,
    OMNIX_CALL_CONNECTED,
    OMNIX_CALL_HELD,
    OMNIX_CALL_ENDING,
    OMNIX_CALL_ENDED,
    OMNIX_CALL_FAILED,
} omnix_call_state_t;

typedef enum {
    OMNIX_ERR_OK = 0,
    OMNIX_ERR_INITIALIZATION,
    OMNIX_ERR_INVALID_CONFIG,
    OMNIX_ERR_REGISTRATION_FAILED,
    OMNIX_ERR_AUTH_FAILED,
    OMNIX_ERR_NETWORK,
    OMNIX_ERR_TLS,
    OMNIX_ERR_MEDIA,
    OMNIX_ERR_CALL_FAILED,
    OMNIX_ERR_CALL_BUSY,
    OMNIX_ERR_CALL_REJECTED,
    OMNIX_ERR_TIMEOUT,
    OMNIX_ERR_NOT_REGISTERED,
    OMNIX_ERR_INVALID_STATE,
    OMNIX_ERR_PERMISSION_DENIED,
    OMNIX_ERR_TRANSFER_FAILED,
    OMNIX_ERR_NOT_SUPPORTED,
    OMNIX_ERR_INTERNAL,
} omnix_error_t;

typedef struct {
    char call_id[128];
    char peer_uri[256];
    char peer_display_name[128];
    omnix_call_state_t state;
    bool is_outgoing;
    bool is_muted;
    bool is_on_hold;
} omnix_call_info_t;

typedef void (*omnix_reg_state_cb)(omnix_reg_state_t state, int sip_code,
                                   const char *reason, void *ctx);
typedef void (*omnix_call_event_cb)(omnix_call_state_t state,
                                    const omnix_call_info_t *call, void *ctx);
typedef void (*omnix_error_cb)(omnix_error_t err, const char *detail, void *ctx);

typedef struct {
    const char *sip_server;
    const char *sip_user;
    const char *auth_user;
    const char *sip_password;
    const char *display_name;
    const char *stun_server;
    /* MUST default to true (Issue #1 §16 / SDK-025). Never ship false silently. */
    bool verify_tls_cert;
    /*
     * MUST default to true (Issue #1 §16 / SDK-026). MVP always forces
     * account mediaenc to dtls_srtp; false logs a WARNING and still encrypts.
     */
    bool enable_srtp;
    const char *audio_module;
    /*
     * Comma-separated codec preference (default when NULL/empty:
     * "opus,pcmu,pcma"). Codecs not compiled in are ignored with a WARNING;
     * if none remain → OMNIX_ERR_INVALID_CONFIG (SDK-027). Opus requires
     * SDK-067; until then G.711 (pcmu/pcma) is the mandatory baseline.
     */
    const char *codecs;
    omnix_reg_state_cb on_reg_state;
    omnix_call_event_cb on_call_event;
    omnix_error_cb on_error;
    void *ctx;
} omnix_config_t;

#ifdef __cplusplus
}
#endif

#endif /* OMNIX_VOICE_OMNIX_TYPES_H */
