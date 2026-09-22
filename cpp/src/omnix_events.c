/**
 * Omnix Voice — mqueue event dispatch (SDK-011/013).
 * App→re commands and registration callbacks use this queue.
 * Baresip bevent callbacks are deferred via mqueue before on_reg_state.
 */
#include "omnix_internal.h"

#include <re.h>
#include <baresip.h>

#include <ctype.h>
#include <stdlib.h>
#include <string.h>

enum {
	OMNIX_MQ_RE_READY = 1,
	OMNIX_MQ_SHUTDOWN = 2,
	OMNIX_MQ_REG_STATE = 3,
};

struct omnix_reg_notify {
	omnix_reg_state_t state;
	int sip_code;
	char reason[160];
};

static bool g_bevent_registered;

/**
 * Parse Baresip reg text ("200 OK", "401 Unauthorized", "%m" errno).
 * Never treats the text as a password — numeric SIP code + remainder only.
 */
static void omnix_parse_reg_text(const char *txt, int *sip_code,
				 char *reason, size_t reason_sz)
{
	const char *p;
	char *end = NULL;
	long code;

	if (sip_code) {
		*sip_code = 0;
	}
	if (reason && reason_sz) {
		reason[0] = '\0';
	}
	if (!txt || !txt[0]) {
		return;
	}

	p = txt;
	while (*p && isspace((unsigned char)*p)) {
		++p;
	}

	code = strtol(p, &end, 10);
	if (end != p && code > 0 && code < 1000) {
		if (sip_code) {
			*sip_code = (int)code;
		}
		p = end;
		while (*p && isspace((unsigned char)*p)) {
			++p;
		}
		if (reason && reason_sz) {
			str_ncpy(reason, p, reason_sz);
		}
		return;
	}

	/* Non-numeric (e.g. strerror from transport err → Baresip uses 999). */
	if (sip_code) {
		*sip_code = 999;
	}
	if (reason && reason_sz) {
		str_ncpy(reason, txt, reason_sz);
	}
}

static int omnix_events_push_reg_state(omnix_reg_state_t state, int sip_code,
				       const char *reason)
{
	struct omnix_state *st = omnix_state_get();
	struct omnix_reg_notify *n;
	struct mqueue *mq;
	int err;

	if (!st || !st->mqueue) {
		return EINVAL;
	}
	mq = st->mqueue;

	n = mem_zalloc(sizeof(*n), NULL);
	if (!n) {
		return ENOMEM;
	}
	n->state = state;
	n->sip_code = sip_code;
	if (reason && reason[0] != '\0') {
		str_ncpy(n->reason, reason, sizeof(n->reason));
	}

	err = mqueue_push(mq, OMNIX_MQ_REG_STATE, n);
	if (err) {
		mem_deref(n);
	}
	return err;
}

/**
 * Apply registration state, then notify the app via mqueue (not inline from
 * the Baresip bevent stack).
 */
static void omnix_reg_apply(omnix_reg_state_t state, int sip_code,
			    const char *reason)
{
	struct omnix_state *st = omnix_state_get();

	if (!st) {
		return;
	}

	st->reg_state = state;
	if (state == OMNIX_REG_UNREGISTERED || state == OMNIX_REG_FAILED ||
	    state == OMNIX_REG_REGISTERED) {
		st->unregister_pending = false;
	}
	if (state == OMNIX_REG_REGISTERING) {
		st->unregister_pending = false;
	}

	/* Teardown: ua_destructor emits UNREGISTERING after re_cancel — do
	 * not enqueue; those payloads would leak when mqueue is destroyed. */
	if (st->shutting_down) {
		return;
	}

	(void)omnix_events_push_reg_state(state, sip_code, reason);
}

static void omnix_bevent_handler(enum bevent_ev ev, struct bevent *event,
				 void *arg)
{
	struct omnix_state *st = omnix_state_get();
	struct ua *ua;
	const char *txt;
	int sip_code = 0;
	char reason[160];

	(void)arg;

	if (!st || !st->initialized) {
		return;
	}

	ua = bevent_get_ua(event);
	if (st->ua && ua && ua != st->ua) {
		return;
	}

	txt = bevent_get_text(event);
	reason[0] = '\0';
	omnix_parse_reg_text(txt, &sip_code, reason, sizeof(reason));

	switch (ev) {
	case BEVENT_REGISTERING:
		/* omnix_register already sets REGISTERING; avoid duplicate. */
		if (st->reg_state != OMNIX_REG_REGISTERING) {
			omnix_reg_apply(OMNIX_REG_REGISTERING, 0, NULL);
		}
		break;

	case BEVENT_REGISTER_OK:
		/*
		 * Successful expire=0 unregister also emits REGISTER_OK in
		 * Baresip 4.11. Map to UNREGISTERED when unregister pending.
		 */
		if (st->unregister_pending) {
			omnix_reg_apply(OMNIX_REG_UNREGISTERED, sip_code,
					reason[0] ? reason : "OK");
		}
		else {
			omnix_reg_apply(OMNIX_REG_REGISTERED, sip_code,
					reason[0] ? reason : "OK");
		}
		break;

	case BEVENT_REGISTER_FAIL:
		omnix_reg_apply(OMNIX_REG_FAILED, sip_code,
				reason[0] ? reason : "register failed");
		break;

	case BEVENT_UNREGISTERING:
		/*
		 * Baresip 4.11 has no BEVENT_UNREGISTERED; UNREGISTERING is
		 * the UA-event counterpart (Issue #2 maps → UNREGISTERED).
		 * Final confirmation may also arrive as REGISTER_OK (above).
		 */
		st->unregister_pending = true;
		omnix_reg_apply(OMNIX_REG_UNREGISTERED, 0, NULL);
		break;

	default:
		break;
	}
}

static void omnix_mqueue_handler(int id, void *data, void *arg)
{
	(void)arg;

	switch (id) {
	case OMNIX_MQ_RE_READY:
		omnix_lifecycle_on_re_ready();
		break;
	case OMNIX_MQ_SHUTDOWN: {
		struct omnix_state *st = omnix_state_get();
		/*
		 * Runs on the re_main thread. Prefer SIP exit path; always
		 * re_cancel so the poll loop stops even when no UA exists.
		 * Mark shutting_down first so ua_destructor's UNREGISTERING
		 * does not enqueue leaked reg-notify messages.
		 */
		if (st) {
			st->shutting_down = true;
		}
		ua_stop_all(false);
		re_cancel();
		break;
	}
	case OMNIX_MQ_REG_STATE: {
		struct omnix_reg_notify *n = data;
		struct omnix_state *st = omnix_state_get();
		omnix_reg_state_cb cb;
		void *ctx;

		if (n && st) {
			cb = st->config.on_reg_state;
			ctx = st->config.ctx;
			if (cb) {
				cb(n->state, n->sip_code,
				   n->reason[0] ? n->reason : NULL, ctx);
			}
		}
		mem_deref(n);
		break;
	}
	default:
		/* Call command IDs land in later SDK tasks. */
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

	err = bevent_register(omnix_bevent_handler, NULL);
	if (err) {
		st->mqueue = NULL;
		mem_deref(mq);
		return OMNIX_ERR_INITIALIZATION;
	}
	g_bevent_registered = true;

	return OMNIX_ERR_OK;
}

void omnix_events_shutdown(void)
{
	struct omnix_state *st = omnix_state_get();
	struct mqueue *mq;

	if (g_bevent_registered) {
		bevent_unregister(omnix_bevent_handler);
		g_bevent_registered = false;
	}

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

/**
 * Notify REGISTERING from omnix_register (app thread) via mqueue.
 */
int omnix_events_notify_registering(void)
{
	struct omnix_state *st = omnix_state_get();

	if (!st) {
		return EINVAL;
	}
	st->reg_state = OMNIX_REG_REGISTERING;
	st->unregister_pending = false;
	return omnix_events_push_reg_state(OMNIX_REG_REGISTERING, 0, NULL);
}

/**
 * Notify an arbitrary reg state from the app thread via mqueue.
 */
int omnix_events_notify_reg_state(omnix_reg_state_t state, int sip_code,
				  const char *reason)
{
	struct omnix_state *st = omnix_state_get();

	if (!st) {
		return EINVAL;
	}
	st->reg_state = state;
	if (state == OMNIX_REG_UNREGISTERED || state == OMNIX_REG_FAILED ||
	    state == OMNIX_REG_REGISTERED) {
		st->unregister_pending = false;
	}
	return omnix_events_push_reg_state(state, sip_code, reason);
}

/**
 * Test helper: inject a registration bevent as if from Baresip.
 * kind: 0=REGISTER_OK, 1=REGISTER_FAIL, 2=UNREGISTERING.
 */
int omnix_test_inject_reg_bevent(int kind, const char *text)
{
	struct omnix_state *st = omnix_state_get();
	enum bevent_ev ev;
	int err;

	if (!st || !st->initialized || !st->ua) {
		return EINVAL;
	}

	switch (kind) {
	case 0:
		ev = BEVENT_REGISTER_OK;
		break;
	case 1:
		ev = BEVENT_REGISTER_FAIL;
		break;
	case 2:
		ev = BEVENT_UNREGISTERING;
		break;
	default:
		return EINVAL;
	}

	re_thread_enter();
	err = bevent_ua_emit(ev, st->ua, "%s", text ? text : "");
	re_thread_leave();
	return err;
}
