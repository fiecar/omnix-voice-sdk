/**
 * Omnix Voice — call control stubs (SDK-010).
 */
#include "omnix_internal.h"

#include <string.h>

omnix_error_t omnix_call_make(const char *destination, char *call_id_out,
			      size_t call_id_len)
{
	(void)destination;
	if (call_id_out && call_id_len > 0) {
		call_id_out[0] = '\0';
	}
	return OMNIX_ERR_NOT_SUPPORTED;
}

omnix_error_t omnix_call_answer(const char *call_id)
{
	(void)call_id;
	return OMNIX_ERR_NOT_SUPPORTED;
}

omnix_error_t omnix_call_reject(const char *call_id)
{
	(void)call_id;
	return OMNIX_ERR_NOT_SUPPORTED;
}

omnix_error_t omnix_call_hangup(const char *call_id)
{
	(void)call_id;
	return OMNIX_ERR_NOT_SUPPORTED;
}

omnix_error_t omnix_call_hold(const char *call_id)
{
	(void)call_id;
	return OMNIX_ERR_NOT_SUPPORTED;
}

omnix_error_t omnix_call_resume(const char *call_id)
{
	(void)call_id;
	return OMNIX_ERR_NOT_SUPPORTED;
}

omnix_error_t omnix_call_set_mute(const char *call_id, bool mute)
{
	(void)call_id;
	(void)mute;
	return OMNIX_ERR_NOT_SUPPORTED;
}

omnix_error_t omnix_call_send_dtmf(const char *call_id, char digit)
{
	(void)call_id;
	(void)digit;
	return OMNIX_ERR_NOT_SUPPORTED;
}

omnix_error_t omnix_call_transfer_blind(const char *call_id,
					const char *destination)
{
	(void)call_id;
	(void)destination;
	return OMNIX_ERR_NOT_SUPPORTED;
}

omnix_call_state_t omnix_call_get_state(const char *call_id)
{
	(void)call_id;
	return OMNIX_CALL_IDLE;
}
