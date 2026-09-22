/**
 * Omnix Voice — event dispatch stub (SDK-010).
 * Full mqueue + re_main wiring lands in SDK-011.
 */
#include "omnix_internal.h"

omnix_error_t omnix_events_init(void)
{
	struct omnix_state *st = omnix_state_get();

	if (!st) {
		return OMNIX_ERR_INTERNAL;
	}
	/* mqueue_alloc requires libre init; deferred to SDK-011. */
	st->mqueue = NULL;
	return OMNIX_ERR_OK;
}

void omnix_events_shutdown(void)
{
	struct omnix_state *st = omnix_state_get();

	if (!st) {
		return;
	}
	st->mqueue = NULL;
}
