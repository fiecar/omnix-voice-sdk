/**
 * Omnix Voice — audio / speaker preference (SDK-021).
 *
 * C facade stores speaker_enabled for the platform layer to apply:
 * Android AudioManager.setSpeakerphoneOn (SDK-034 OmnixAudioRouter) and
 * iOS AVAudioSession.overrideOutputAudioPort (SDK-042 OmnixAudioSession).
 * Routing is not applied in this translation unit (no Baresip audio route API).
 */
#include "omnix_internal.h"

omnix_error_t omnix_call_set_speaker(bool enable)
{
	struct omnix_state *st = omnix_state_get();

	if (!st || !st->initialized) {
		return OMNIX_ERR_INVALID_STATE;
	}

	st->speaker_enabled = enable;
	return OMNIX_ERR_OK;
}

int omnix_test_speaker_enabled(void)
{
	struct omnix_state *st = omnix_state_get();

	if (!st || !st->initialized) {
		return -1;
	}
	return st->speaker_enabled ? 1 : 0;
}
