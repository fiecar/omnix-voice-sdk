/**
 * Omnix Voice — mqueue event dispatch (SDK-011).
 * App→re commands and future event fan-out use this queue.
 */
#include "omnix_internal.h"

#include <re.h>
#include <baresip.h>

enum {
	OMNIX_MQ_RE_READY = 1,
	OMNIX_MQ_SHUTDOWN = 2,
};

static void omnix_mqueue_handler(int id, void *data, void *arg)
{
	(void)data;
	(void)arg;

	switch (id) {
	case OMNIX_MQ_RE_READY:
		omnix_lifecycle_on_re_ready();
		break;
	case OMNIX_MQ_SHUTDOWN:
		/*
		 * Runs on the re_main thread. Prefer SIP exit path; always
		 * re_cancel so the poll loop stops even when no UA exists.
		 */
		ua_stop_all(false);
		re_cancel();
		break;
	default:
		/* Call/registration command IDs land in later SDK tasks. */
		break;
	}
}

omnix_error_t omnix_events_init(void)
{
	struct omnix_state *st = omnix_state_get();
	struct mqueue *mq = NULL;
	int err;

	if (!st) {
		return OMNIX_ERR_INTERNAL;
	}

	err = mqueue_alloc(&mq, omnix_mqueue_handler, NULL);
	if (err) {
		return OMNIX_ERR_INITIALIZATION;
	}

	st->mqueue = mq;
	return OMNIX_ERR_OK;
}

void omnix_events_shutdown(void)
{
	struct omnix_state *st = omnix_state_get();
	struct mqueue *mq;

	if (!st || !st->mqueue) {
		return;
	}

	mq = st->mqueue;
	st->mqueue = NULL;
	mem_deref(mq);
}

/**
 * Wake re_main once so callers can wait until the poll loop is live.
 * Safe to call from the app thread after the re thread has been started.
 */
int omnix_events_request_ready_signal(void)
{
	struct omnix_state *st = omnix_state_get();
	struct mqueue *mq;

	if (!st || !st->mqueue) {
		return EINVAL;
	}
	mq = st->mqueue;
	return mqueue_push(mq, OMNIX_MQ_RE_READY, NULL);
}

/**
 * Ask the re thread to stop: ua_stop_all(false) then re_cancel.
 * Safe from the app thread; caller should thrd_join the re thread after.
 */
int omnix_events_request_shutdown(void)
{
	struct omnix_state *st = omnix_state_get();
	struct mqueue *mq;

	if (!st || !st->mqueue) {
		return EINVAL;
	}
	mq = st->mqueue;
	return mqueue_push(mq, OMNIX_MQ_SHUTDOWN, NULL);
}
