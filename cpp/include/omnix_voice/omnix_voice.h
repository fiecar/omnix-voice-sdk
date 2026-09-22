/**
 * Omnix Voice SDK — public C facade (Issue #1 §20A).
 * Stub declarations for SDK-009; implementations land in SDK-010+.
 * Baresip / re types MUST NOT appear in this header.
 */
#ifndef OMNIX_VOICE_OMNIX_VOICE_H
#define OMNIX_VOICE_OMNIX_VOICE_H

#include "omnix_voice/omnix_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Lifecycle */
omnix_error_t omnix_init(const omnix_config_t *config);
void omnix_shutdown(void);

/* Registration */
omnix_error_t omnix_register(void);
void omnix_unregister(void);
omnix_reg_state_t omnix_get_reg_state(void);

/* Call control */
omnix_error_t omnix_call_make(const char *destination, char *call_id_out,
                              size_t call_id_len);
omnix_error_t omnix_call_answer(const char *call_id);
omnix_error_t omnix_call_reject(const char *call_id);
omnix_error_t omnix_call_hangup(const char *call_id);
omnix_error_t omnix_call_hold(const char *call_id);
omnix_error_t omnix_call_resume(const char *call_id);
omnix_error_t omnix_call_set_mute(const char *call_id, bool mute);
omnix_error_t omnix_call_set_speaker(bool enable);
omnix_error_t omnix_call_send_dtmf(const char *call_id, char digit);
omnix_error_t omnix_call_transfer_blind(const char *call_id,
                                        const char *destination);
omnix_call_state_t omnix_call_get_state(const char *call_id);

#ifdef __cplusplus
}
#endif

#endif /* OMNIX_VOICE_OMNIX_VOICE_H */
