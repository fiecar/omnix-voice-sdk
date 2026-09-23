/**
 * Omnix Voice — call registry (SDK-015) + outgoing (SDK-016) + incoming (SDK-017)
 * + answer/reject (SDK-018) + hangup / CLOSED (SDK-019) + mute (SDK-020)
 * + DTMF (SDK-022) + hold/resume (SDK-023).
 *
 * Tracks active calls by call_id. struct call * stays internal only.
 * Slot helpers are intended for use under the re thread lock (SDK-016+).
 * Incoming: foreground lifecycle only (no PushKit/FCM/killed-app wake-up).
 */
#include "omnix_internal.h"

#include <re.h>
#include <baresip.h>

#include <stdio.h>
#include <string.h>

/* baresip internal (core.h): streams are lazy until SDP offer/accept.
 * Host inject never reaches that path — allocate for mute AC checks. */
int call_streams_alloc(struct call *call);

#define OMNIX_MAX_CALLS 8

static omnix_call_entry_t g_calls[OMNIX_MAX_CALLS];
static char g_last_dtmf_digit; /* test observability (SDK-022) */

static void omnix_call_finalize_closed(omnix_call_entry_t *entry,
				       struct call *call, const char *str);

static void omnix_ncpy(char *dst, size_t dst_sz, const char *src)
{
	if (!dst || dst_sz == 0) {
		return;
	}
	if (!src) {
		dst[0] = '\0';
		return;
	}
	str_ncpy(dst, src, dst_sz);
}

static omnix_call_state_t omnix_map_baresip_call_state(const struct call *call)
{
	enum call_state st;

	if (!call) {
		return OMNIX_CALL_IDLE;
	}
	if (call_is_onhold(call)) {
		return OMNIX_CALL_HELD;
	}
	st = call_state(call);
	switch (st) {
	case CALL_STATE_IDLE:
		return OMNIX_CALL_IDLE;
	case CALL_STATE_INCOMING:
		return OMNIX_CALL_INCOMING;
	case CALL_STATE_OUTGOING:
		return OMNIX_CALL_OUTGOING;
	case CALL_STATE_RINGING:
		return OMNIX_CALL_RINGING;
	case CALL_STATE_EARLY:
		return OMNIX_CALL_EARLY_MEDIA;
	case CALL_STATE_ESTABLISHED:
		return OMNIX_CALL_CONNECTED;
	case CALL_STATE_TERMINATED:
		return OMNIX_CALL_ENDED;
	case CALL_STATE_TRANSFER:
	case CALL_STATE_UNKNOWN:
	default:
		return OMNIX_CALL_IDLE;
	}
}

void omnix_call_info_from_baresip(omnix_call_info_t *info, struct call *call)
{
	bool muted = false;

	if (!info) {
		return;
	}
	/* Preserve Omnix-owned mute across refresh when info already set. */
	muted = info->is_muted;
	memset(info, 0, sizeof(*info));
	if (!call) {
		return;
	}
	omnix_ncpy(info->call_id, sizeof(info->call_id), call_id(call));
	omnix_ncpy(info->peer_uri, sizeof(info->peer_uri), call_peeruri(call));
	omnix_ncpy(info->peer_display_name, sizeof(info->peer_display_name),
		   call_peername(call));
	info->state = omnix_map_baresip_call_state(call);
	info->is_outgoing = call_is_outgoing(call);
	info->is_on_hold = call_is_onhold(call);
	info->is_muted = muted;
}

void omnix_call_registry_reset(void)
{
	memset(g_calls, 0, sizeof(g_calls));
}

omnix_call_entry_t *omnix_find_call_by_id(const char *call_id)
{
	int i;

	if (!call_id || call_id[0] == '\0') {
		return NULL;
	}
	for (i = 0; i < OMNIX_MAX_CALLS; ++i) {
		if (g_calls[i].baresip_call &&
		    g_calls[i].call_id[0] != '\0' &&
		    strcmp(g_calls[i].call_id, call_id) == 0) {
			return &g_calls[i];
		}
	}
	return NULL;
}

omnix_call_entry_t *omnix_find_call_by_ptr(const struct call *call)
{
	int i;

	if (!call) {
		return NULL;
	}
	for (i = 0; i < OMNIX_MAX_CALLS; ++i) {
		if (g_calls[i].baresip_call == call) {
			return &g_calls[i];
		}
	}
	return NULL;
}

omnix_call_entry_t *omnix_alloc_call_slot(struct call *call)
{
	const char *id;
	omnix_call_entry_t *entry;
	int i;

	if (!call) {
		return NULL;
	}
	entry = omnix_find_call_by_ptr(call);
	if (entry) {
		omnix_call_info_from_baresip(&entry->info, call);
		omnix_ncpy(entry->call_id, sizeof(entry->call_id),
			   call_id(call));
		return entry;
	}

	id = call_id(call);
	if (!id || id[0] == '\0') {
		return NULL;
	}
	if (omnix_find_call_by_id(id)) {
		return NULL; /* duplicate call_id */
	}

	for (i = 0; i < OMNIX_MAX_CALLS; ++i) {
		if (g_calls[i].baresip_call == NULL) {
			entry = &g_calls[i];
			memset(entry, 0, sizeof(*entry));
			entry->baresip_call = call;
			omnix_ncpy(entry->call_id, sizeof(entry->call_id), id);
			omnix_call_info_from_baresip(&entry->info, call);
			return entry;
		}
	}
	return NULL; /* registry full */
}

void omnix_free_call_slot(omnix_call_entry_t *entry)
{
	if (!entry) {
		return;
	}
	memset(entry, 0, sizeof(*entry));
}

unsigned omnix_call_registry_count(void)
{
	unsigned n = 0;
	int i;

	for (i = 0; i < OMNIX_MAX_CALLS; ++i) {
		if (g_calls[i].baresip_call != NULL) {
			++n;
		}
	}
	return n;
}

unsigned omnix_call_registry_capacity(void)
{
	return OMNIX_MAX_CALLS;
}

omnix_call_entry_t *omnix_test_install_call_slot(const char *call_id,
						 struct call *fake_ptr)
{
	omnix_call_entry_t *entry;
	int i;

	if (!call_id || call_id[0] == '\0' || !fake_ptr) {
		return NULL;
	}
	if (omnix_find_call_by_id(call_id) || omnix_find_call_by_ptr(fake_ptr)) {
		return NULL;
	}
	for (i = 0; i < OMNIX_MAX_CALLS; ++i) {
		if (g_calls[i].baresip_call == NULL) {
			entry = &g_calls[i];
			memset(entry, 0, sizeof(*entry));
			entry->baresip_call = fake_ptr;
			omnix_ncpy(entry->call_id, sizeof(entry->call_id),
				   call_id);
			omnix_ncpy(entry->info.call_id, sizeof(entry->info.call_id),
				   call_id);
			entry->info.state = OMNIX_CALL_IDLE;
			return entry;
		}
	}
	return NULL;
}

int omnix_test_make_baresip_outgoing_call(struct call **callp,
					  const char *peer_uri)
{
	struct omnix_state *st;
	struct call *call = NULL;
	struct pl pl;
	int err;

	if (!callp || !peer_uri || peer_uri[0] == '\0') {
		return EINVAL;
	}
	*callp = NULL;
	st = omnix_state_get();
	if (!st || !st->initialized || !st->ua) {
		return EINVAL;
	}

	re_thread_enter();
	err = ua_call_alloc(&call, st->ua, VIDMODE_OFF, NULL, NULL, NULL,
			    false);
	if (err) {
		re_thread_leave();
		return err;
	}

	pl_set_str(&pl, peer_uri);
	/*
	 * call_connect sets id / peer_uri / outgoing before send_invite.
	 * Invite may fail (no network) — still usable for registry populate.
	 */
	(void)call_connect(call, &pl);
	if (!call_id(call) || call_id(call)[0] == '\0') {
		mem_deref(call);
		re_thread_leave();
		return EPROTO;
	}
	*callp = call;
	re_thread_leave();
	return 0;
}

void omnix_test_release_baresip_call(struct call *call)
{
	if (!call) {
		return;
	}
	re_thread_enter();
	call_hangup(call, 0, NULL);
	mem_deref(call);
	re_thread_leave();
}

/**
 * Test helper (SDK-020): ensure audio stream exists (call_streams_alloc) so
 * call_set_audio_ldir / call_get_mdir can be asserted on host inject calls.
 * Returns 0 on success, else errno-style code.
 */
int omnix_test_ensure_call_audio(const char *call_id)
{
	omnix_call_entry_t *entry;
	struct call *call;
	int err = 0;

	if (!call_id || call_id[0] == '\0') {
		return EINVAL;
	}

	re_thread_enter();
	entry = omnix_find_call_by_id(call_id);
	if (!entry || !entry->baresip_call) {
		re_thread_leave();
		return ENOENT;
	}
	call = entry->baresip_call;
	if (!call_audio(call)) {
		err = call_streams_alloc(call);
		if (!err) {
			call_set_mdir(call, SDP_SENDRECV, SDP_SENDRECV);
		}
	}
	re_thread_leave();
	return err;
}

/**
 * Test helper (SDK-020): read local audio direction via call_get_mdir
 * (same stream_ldir path that call_set_audio_ldir updates).
 * Returns enum sdp_dir (0…3) or -1 if call/audio stream missing.
 */
int omnix_test_call_audio_ldir(const char *call_id)
{
	omnix_call_entry_t *entry;
	struct call *call;
	enum sdp_dir adir = SDP_INACTIVE;
	enum sdp_dir vdir = SDP_INACTIVE;
	struct audio *au;
	struct stream *strm;

	if (!call_id || call_id[0] == '\0') {
		return -1;
	}

	re_thread_enter();
	entry = omnix_find_call_by_id(call_id);
	if (!entry || !entry->baresip_call) {
		re_thread_leave();
		return -1;
	}
	call = entry->baresip_call;
	au = call_audio(call);
	strm = audio_strm(au);
	if (!au || !strm) {
		re_thread_leave();
		return -1;
	}
	call_get_mdir(call, &adir, &vdir);
	(void)vdir;
	re_thread_leave();
	return (int)adir;
}

/**
 * Test helper (SDK-019): simulate CALL_EVENT_CLOSED with optional SIP text
 * (e.g. "486 Busy Here") so FAILED vs ENDED can be asserted without live SIP.
 */
int omnix_test_inject_call_closed(const char *call_id, const char *str)
{
	omnix_call_entry_t *entry;
	struct call *call;

	if (!call_id || call_id[0] == '\0') {
		return EINVAL;
	}

	re_thread_enter();
	entry = omnix_find_call_by_id(call_id);
	if (!entry || !entry->baresip_call) {
		re_thread_leave();
		return ENOENT;
	}
	call = entry->baresip_call;
	bevent_call_emit(BEVENT_CALL_CLOSED, call, "%s", str ? str : "");
	omnix_call_finalize_closed(entry, call, str);
	re_thread_leave();
	return 0;
}

/**
 * Test helper (SDK-017): allocate a call with id/peer, then emit
 * BEVENT_CALL_INCOMING so omnix_bevent_handler runs the incoming path
 * without a live SIP INVITE (host CI has no TLS peer).
 */
int omnix_test_inject_incoming_bevent(const char *peer_uri)
{
	struct call *call = NULL;
	const char *peer;
	int err;

	err = omnix_test_make_baresip_outgoing_call(&call, peer_uri);
	if (err || !call) {
		return err ? err : EINVAL;
	}

	peer = call_peeruri(call);
	if (!peer || peer[0] == '\0') {
		peer = peer_uri;
	}

	re_thread_enter();
	err = bevent_call_emit(BEVENT_CALL_INCOMING, call, "%s",
			       peer ? peer : "");
	re_thread_leave();
	return err;
}

/**
 * Issue #1 §21: ENDED = CLOSED; FAILED = CLOSED + non-zero SIP code.
 * Prefer call_scode(); fall back to a leading 3xx–6xx in the CLOSED text.
 */
static int omnix_closed_sip_code(const struct call *call, const char *str)
{
	uint16_t sc;
	unsigned code = 0;

	sc = call_scode(call);
	if (sc != 0) {
		return (int)sc;
	}
	if (str && str[0] != '\0' && sscanf(str, "%u", &code) == 1 &&
	    code >= 300 && code <= 699) {
		return (int)code;
	}
	return 0;
}

/**
 * Finalize a closed call under the re lock: notify ENDED/FAILED, free slot,
 * mem_deref. Safe if entry is already cleared (still deref the call).
 */
static void omnix_call_finalize_closed(omnix_call_entry_t *entry,
				       struct call *call, const char *str)
{
	omnix_call_state_t st;
	int sip_code;

	if (!call) {
		return;
	}

	sip_code = omnix_closed_sip_code(call, str);
	st = (sip_code != 0) ? OMNIX_CALL_FAILED : OMNIX_CALL_ENDED;

	if (entry && entry->baresip_call == call) {
		omnix_call_info_from_baresip(&entry->info, call);
		entry->info.state = st;
		(void)omnix_events_notify_call_state(st, &entry->info);
		omnix_free_call_slot(entry);
	}
	mem_deref(call);
}

/**
 * Call-level event hook (SDK-016+). Installed after ua_connect succeeds.
 * CALL_EVENT_OUTGOING already fired under the UA handler during connect;
 * we still handle it here for any later re-fire and map CLOSED lifetime.
 */
static void omnix_call_event_handler(struct call *call, enum call_event ev,
				     const char *str, void *arg)
{
	omnix_call_entry_t *entry = arg;
	const char *peeruri;

	if (!call) {
		return;
	}

	peeruri = call_peeruri(call);

	switch (ev) {
	case CALL_EVENT_OUTGOING:
		if (entry) {
			omnix_call_info_from_baresip(&entry->info, call);
			entry->info.state = OMNIX_CALL_OUTGOING;
			(void)omnix_events_notify_call_state(OMNIX_CALL_OUTGOING,
							       &entry->info);
		}
		if (peeruri) {
			bevent_call_emit(BEVENT_CALL_OUTGOING, call, "%s",
					 peeruri);
		}
		break;

	case CALL_EVENT_RINGING:
		if (peeruri) {
			bevent_call_emit(BEVENT_CALL_RINGING, call, "%s",
					 peeruri);
		}
		break;

	case CALL_EVENT_PROGRESS:
		if (peeruri) {
			bevent_call_emit(BEVENT_CALL_PROGRESS, call, "%s",
					 peeruri);
		}
		break;

	case CALL_EVENT_ANSWERED:
		if (peeruri) {
			bevent_call_emit(BEVENT_CALL_ANSWERED, call, "%s",
					 peeruri);
		}
		break;

	case CALL_EVENT_ESTABLISHED:
		if (peeruri) {
			bevent_call_emit(BEVENT_CALL_ESTABLISHED, call, "%s",
					 peeruri);
		}
		break;

	case CALL_EVENT_CLOSED:
		/* SDK-019: ENDED/FAILED + free slot + on_call_event. */
		bevent_call_emit(BEVENT_CALL_CLOSED, call, "%s",
				 str ? str : "");
		omnix_call_finalize_closed(entry, call, str);
		break;

	case CALL_EVENT_TRANSFER:
		bevent_call_emit(BEVENT_CALL_TRANSFER, call, "%s",
				 str ? str : "");
		break;

	case CALL_EVENT_TRANSFER_FAILED:
		bevent_call_emit(BEVENT_CALL_TRANSFER_FAILED, call, "%s",
				 str ? str : "");
		break;

	case CALL_EVENT_INCOMING:
		/*
		 * Primary INCOMING path is BEVENT_CALL_INCOMING →
		 * omnix_call_handle_incoming (handlers replaced after that).
		 * Re-fire here if our hook already owns the call.
		 */
		if (entry) {
			omnix_call_info_from_baresip(&entry->info, call);
			entry->info.state = OMNIX_CALL_INCOMING;
			entry->info.is_outgoing = false;
			(void)omnix_events_notify_call_state(OMNIX_CALL_INCOMING,
							       &entry->info);
		}
		break;

	case CALL_EVENT_MENC:
	default:
		break;
	}
}

/**
 * SDK-017: BEVENT_CALL_INCOMING (UA CALL_EVENT_INCOMING) while process is
 * alive / SDK registered. Must run under the re lock; app callback via mqueue.
 */
void omnix_call_handle_incoming(struct call *call)
{
	omnix_call_entry_t *entry;

	if (!call) {
		return;
	}

	entry = omnix_alloc_call_slot(call);
	if (!entry) {
		call_hangup(call, 486, "Busy Here");
		return;
	}

	call_set_handlers(call, omnix_call_event_handler, NULL, entry);

	omnix_call_info_from_baresip(&entry->info, call);
	entry->info.state = OMNIX_CALL_INCOMING;
	entry->info.is_outgoing = false;

	(void)omnix_events_notify_call_state(OMNIX_CALL_INCOMING, &entry->info);
}

static omnix_error_t omnix_map_connect_err(int err)
{
	switch (err) {
	case 0:
		return OMNIX_ERR_OK;
	case EINVAL:
		return OMNIX_ERR_INVALID_CONFIG;
	case EACCES:
		return OMNIX_ERR_PERMISSION_DENIED;
	case ENOMEM:
		return OMNIX_ERR_INTERNAL;
	default:
		return OMNIX_ERR_CALL_FAILED;
	}
}

omnix_error_t omnix_call_make(const char *destination, char *call_id_out,
			      size_t call_id_len)
{
	struct omnix_state *st = omnix_state_get();
	struct call *call = NULL;
	omnix_call_entry_t *entry;
	int err;

	if (call_id_out && call_id_len > 0) {
		call_id_out[0] = '\0';
	}

	if (!st || !st->initialized || !st->ua) {
		return OMNIX_ERR_INVALID_STATE;
	}
	if (!destination || destination[0] == '\0') {
		return OMNIX_ERR_INVALID_CONFIG;
	}
	if (!call_id_out ||
	    call_id_len < sizeof(((omnix_call_info_t *)0)->call_id)) {
		return OMNIX_ERR_INVALID_CONFIG;
	}
	if (st->reg_state != OMNIX_REG_REGISTERED) {
		return OMNIX_ERR_NOT_REGISTERED;
	}

	re_thread_enter();
	/*
	 * Issue #2: ua_connect(ua, &call, NULL, destination, VIDMODE_OFF).
	 * Baresip's ua_connect mem_deref's the call if call_connect fails
	 * (e.g. ENOSYS when no TLS peer in host CI) — after CALL_EVENT_OUTGOING
	 * already fired. Use the same alloc+connect sequence but keep the call
	 * when call_id was assigned so OUTGOING can be delivered to the app.
	 */
	err = ua_call_alloc(&call, st->ua, VIDMODE_OFF, NULL, NULL, NULL, true);
	if (err || !call) {
		re_thread_leave();
		return omnix_map_connect_err(err ? err : ENOMEM);
	}

	{
		struct pl pl;

		pl_set_str(&pl, destination);
		err = call_connect(call, &pl);
	}
	if (!call_id(call) || call_id(call)[0] == '\0') {
		mem_deref(call);
		re_thread_leave();
		return omnix_map_connect_err(err ? err : EPROTO);
	}
	(void)err; /* invite/transport may fail offline; call stays OUTGOING */

	entry = omnix_alloc_call_slot(call);
	if (!entry) {
		/* UA call eh still installed — hangup → CLOSED → mem_deref. */
		call_hangup(call, 486, "Busy Here");
		re_thread_leave();
		return OMNIX_ERR_CALL_BUSY;
	}

	/* Replace UA call eh with Omnix hook (OUTGOING already emitted once). */
	call_set_handlers(call, omnix_call_event_handler, NULL, entry);

	entry->info.state = OMNIX_CALL_OUTGOING;
	omnix_ncpy(call_id_out, call_id_len, entry->call_id);

	/*
	 * CALL_EVENT_OUTGOING fired during ua_connect under the UA handler
	 * (before our hook was installed). Push the app callback now via
	 * mqueue so on_call_event runs outside the re lock.
	 */
	(void)omnix_events_notify_call_state(OMNIX_CALL_OUTGOING, &entry->info);

	re_thread_leave();
	return OMNIX_ERR_OK;
}

omnix_error_t omnix_call_answer(const char *call_id)
{
	struct omnix_state *st = omnix_state_get();
	omnix_call_entry_t *entry;
	int err;

	if (!st || !st->initialized) {
		return OMNIX_ERR_INVALID_STATE;
	}
	if (!call_id || call_id[0] == '\0') {
		return OMNIX_ERR_INVALID_STATE;
	}

	re_thread_enter();
	entry = omnix_find_call_by_id(call_id);
	if (!entry || !entry->baresip_call) {
		re_thread_leave();
		return OMNIX_ERR_INVALID_STATE;
	}

	/* Issue #2 SDK-018: SIP 200 OK, audio-only. */
	err = call_answer(entry->baresip_call, 200, VIDMODE_OFF);
	if (err) {
		re_thread_leave();
		if (err == EINVAL || err == EAGAIN) {
			return OMNIX_ERR_INVALID_STATE;
		}
		return OMNIX_ERR_CALL_FAILED;
	}

	omnix_call_info_from_baresip(&entry->info, entry->baresip_call);
	re_thread_leave();
	return OMNIX_ERR_OK;
}

omnix_error_t omnix_call_reject(const char *call_id)
{
	struct omnix_state *st = omnix_state_get();
	omnix_call_entry_t *entry;
	struct call *call;
	char idbuf[sizeof(((omnix_call_info_t *)0)->call_id)];

	if (!st || !st->initialized) {
		return OMNIX_ERR_INVALID_STATE;
	}
	if (!call_id || call_id[0] == '\0') {
		return OMNIX_ERR_INVALID_STATE;
	}

	re_thread_enter();
	entry = omnix_find_call_by_id(call_id);
	if (!entry || !entry->baresip_call) {
		re_thread_leave();
		return OMNIX_ERR_INVALID_STATE;
	}

	omnix_ncpy(idbuf, sizeof(idbuf), call_id);
	call = entry->baresip_call;
	/*
	 * Issue #2 SDK-018: SIP 486 Busy Here. True INCOMING + sess may fire
	 * CALL_EVENT_CLOSED (ENDED/FAILED + slot free + mem_deref) before
	 * hangup returns. Host-injected / no-sess calls skip CLOSED — finish
	 * lifetime here with the reject SIP code (FAILED).
	 */
	call_hangup(call, 486, "Busy Here");
	entry = omnix_find_call_by_id(idbuf);
	if (entry && entry->baresip_call == call) {
		omnix_call_finalize_closed(entry, call, "486 Busy Here");
	}
	re_thread_leave();
	return OMNIX_ERR_OK;
}

omnix_error_t omnix_call_hangup(const char *call_id)
{
	struct omnix_state *st = omnix_state_get();
	omnix_call_entry_t *entry;
	struct call *call;
	char idbuf[sizeof(((omnix_call_info_t *)0)->call_id)];

	if (!st || !st->initialized) {
		return OMNIX_ERR_INVALID_STATE;
	}
	if (!call_id || call_id[0] == '\0') {
		return OMNIX_ERR_INVALID_STATE;
	}

	re_thread_enter();
	entry = omnix_find_call_by_id(call_id);
	if (!entry || !entry->baresip_call) {
		re_thread_leave();
		return OMNIX_ERR_INVALID_STATE;
	}

	omnix_ncpy(idbuf, sizeof(idbuf), call_id);
	call = entry->baresip_call;

	/* Issue #1 §21: hangup → ENDING → CLOSED → ENDED/FAILED. */
	entry->info.state = OMNIX_CALL_ENDING;
	(void)omnix_events_notify_call_state(OMNIX_CALL_ENDING, &entry->info);

	/*
	 * Issue #2 SDK-019: call_hangup(call, 0, NULL) under re lock.
	 * Live sess may fire CALL_EVENT_CLOSED before return; host inject
	 * often skips CLOSED — finalize as ENDED (scode 0) if still tracked.
	 */
	call_hangup(call, 0, NULL);
	entry = omnix_find_call_by_id(idbuf);
	if (entry && entry->baresip_call == call) {
		omnix_call_finalize_closed(entry, call, NULL);
	}
	re_thread_leave();
	return OMNIX_ERR_OK;
}

omnix_error_t omnix_call_hold(const char *call_id)
{
	struct omnix_state *st = omnix_state_get();
	omnix_call_entry_t *entry;
	struct call *call;
	int err;
	bool muted;

	if (!st || !st->initialized) {
		return OMNIX_ERR_INVALID_STATE;
	}
	if (!call_id || call_id[0] == '\0') {
		return OMNIX_ERR_INVALID_STATE;
	}

	re_thread_enter();
	entry = omnix_find_call_by_id(call_id);
	if (!entry || !entry->baresip_call) {
		re_thread_leave();
		return OMNIX_ERR_INVALID_STATE;
	}

	/*
	 * Issue #2 SDK-023: hold only from CONNECTED (Omnix entry state).
	 * call_hold(call, true) under re lock; fire HELD on success.
	 */
	if (entry->info.state != OMNIX_CALL_CONNECTED) {
		re_thread_leave();
		return OMNIX_ERR_INVALID_STATE;
	}

	call = entry->baresip_call;
	muted = entry->info.is_muted;
	err = call_hold(call, true);
	/*
	 * call_hold sets on_hold before call_modify. Host inject may lack a
	 * usable sess (EINVAL) or modify may fail offline — accept only when
	 * Baresip reports on-hold so we never invent HELD without call_hold.
	 */
	if (call_is_onhold(call)) {
		omnix_call_info_from_baresip(&entry->info, call);
		entry->info.is_muted = muted;
		entry->info.state = OMNIX_CALL_HELD;
		entry->info.is_on_hold = true;
		(void)omnix_events_notify_call_state(OMNIX_CALL_HELD,
						     &entry->info);
		re_thread_leave();
		return OMNIX_ERR_OK;
	}
	re_thread_leave();
	if (err == EINVAL) {
		return OMNIX_ERR_INVALID_STATE;
	}
	return OMNIX_ERR_CALL_FAILED;
}

omnix_error_t omnix_call_resume(const char *call_id)
{
	struct omnix_state *st = omnix_state_get();
	omnix_call_entry_t *entry;
	struct call *call;
	int err;
	bool muted;

	if (!st || !st->initialized) {
		return OMNIX_ERR_INVALID_STATE;
	}
	if (!call_id || call_id[0] == '\0') {
		return OMNIX_ERR_INVALID_STATE;
	}

	re_thread_enter();
	entry = omnix_find_call_by_id(call_id);
	if (!entry || !entry->baresip_call) {
		re_thread_leave();
		return OMNIX_ERR_INVALID_STATE;
	}

	/*
	 * Issue #2 SDK-023: resume only from HELD.
	 * call_hold(call, false) under re lock; fire CONNECTED on success.
	 */
	if (entry->info.state != OMNIX_CALL_HELD) {
		re_thread_leave();
		return OMNIX_ERR_INVALID_STATE;
	}

	call = entry->baresip_call;
	muted = entry->info.is_muted;
	err = call_hold(call, false);
	if (!call_is_onhold(call)) {
		omnix_call_info_from_baresip(&entry->info, call);
		entry->info.is_muted = muted;
		entry->info.state = OMNIX_CALL_CONNECTED;
		entry->info.is_on_hold = false;
		(void)omnix_events_notify_call_state(OMNIX_CALL_CONNECTED,
						     &entry->info);
		re_thread_leave();
		return OMNIX_ERR_OK;
	}
	re_thread_leave();
	if (err == EINVAL) {
		return OMNIX_ERR_INVALID_STATE;
	}
	return OMNIX_ERR_CALL_FAILED;
}

omnix_error_t omnix_call_set_mute(const char *call_id, bool mute)
{
	struct omnix_state *st = omnix_state_get();
	omnix_call_entry_t *entry;
	struct call *call;
	enum sdp_dir dir;

	if (!st || !st->initialized) {
		return OMNIX_ERR_INVALID_STATE;
	}
	if (!call_id || call_id[0] == '\0') {
		return OMNIX_ERR_INVALID_STATE;
	}

	re_thread_enter();
	entry = omnix_find_call_by_id(call_id);
	if (!entry || !entry->baresip_call) {
		re_thread_leave();
		return OMNIX_ERR_INVALID_STATE;
	}

	call = entry->baresip_call;
	/*
	 * Issue #2 SDK-020: mute = stop local TX via call_set_audio_ldir.
	 * SDP_RECVONLY = local sends nothing (recv-only); SDP_SENDRECV restores TX.
	 * Host unit test (test_mute) asserts sdp_media_ldir after mute/unmute:
	 * muted → SDP_RECVONLY, unmuted → SDP_SENDRECV. Real-device "no audio
	 * sent" is a manual/SDK-065 gate when a live SIP peer is available.
	 */
	dir = mute ? SDP_RECVONLY : SDP_SENDRECV;
	call_set_audio_ldir(call, dir);
	entry->info.is_muted = mute;
	re_thread_leave();
	return OMNIX_ERR_OK;
}

/**
 * Issue #2 SDK-022: digit must be 0-9, *, #, or A-D (case-insensitive a-d).
 * Returns true if valid for RFC 2833 / telephone-event.
 */
static bool omnix_dtmf_digit_valid(char digit)
{
	if (digit >= '0' && digit <= '9') {
		return true;
	}
	if (digit == '*' || digit == '#') {
		return true;
	}
	if (digit >= 'A' && digit <= 'D') {
		return true;
	}
	if (digit >= 'a' && digit <= 'd') {
		return true;
	}
	return false;
}

omnix_error_t omnix_call_send_dtmf(const char *call_id, char digit)
{
	struct omnix_state *st = omnix_state_get();
	omnix_call_entry_t *entry;
	struct call *call;
	int err;

	if (!st || !st->initialized) {
		return OMNIX_ERR_INVALID_STATE;
	}
	if (!call_id || call_id[0] == '\0') {
		return OMNIX_ERR_INVALID_STATE;
	}
	if (!omnix_dtmf_digit_valid(digit)) {
		return OMNIX_ERR_INVALID_CONFIG;
	}

	re_thread_enter();
	entry = omnix_find_call_by_id(call_id);
	if (!entry || !entry->baresip_call) {
		re_thread_leave();
		return OMNIX_ERR_INVALID_STATE;
	}

	call = entry->baresip_call;
	/*
	 * Issue #2 SDK-022: call_send_digit() inside re lock.
	 * KEYCODE_REL ends the tone (baresip menu / test pattern).
	 * Host unit test asserts validation + OK after streams alloc;
	 * "DTMF received by SIP server" is gate H-3 / SDK-065.
	 */
	err = call_send_digit(call, digit);
	if (!err) {
		err = call_send_digit(call, KEYCODE_REL);
	}
	if (!err) {
		g_last_dtmf_digit = digit;
	}
	re_thread_leave();

	if (err == EINVAL) {
		return OMNIX_ERR_INVALID_CONFIG;
	}
	if (err) {
		return OMNIX_ERR_CALL_FAILED;
	}
	return OMNIX_ERR_OK;
}

void omnix_test_reset_last_dtmf(void)
{
	g_last_dtmf_digit = 0;
}

char omnix_test_last_dtmf_digit(void)
{
	return g_last_dtmf_digit;
}

/**
 * Test helper (SDK-023): mark Omnix entry CONNECTED so hold guard can pass.
 * Host inject never reaches ESTABLISHED; live SIP sets CONNECTED via events.
 * Returns 0 on success, else errno-style code.
 */
int omnix_test_force_call_connected(const char *call_id)
{
	omnix_call_entry_t *entry;

	if (!call_id || call_id[0] == '\0') {
		return EINVAL;
	}

	re_thread_enter();
	entry = omnix_find_call_by_id(call_id);
	if (!entry || !entry->baresip_call) {
		re_thread_leave();
		return ENOENT;
	}
	entry->info.state = OMNIX_CALL_CONNECTED;
	entry->info.is_on_hold = false;
	re_thread_leave();
	return 0;
}

/**
 * Test helper (SDK-023): whether Baresip call_is_onhold is true (-1 if missing).
 */
int omnix_test_call_is_onhold(const char *call_id)
{
	omnix_call_entry_t *entry;
	int onhold = -1;

	if (!call_id || call_id[0] == '\0') {
		return -1;
	}

	re_thread_enter();
	entry = omnix_find_call_by_id(call_id);
	if (entry && entry->baresip_call) {
		onhold = call_is_onhold(entry->baresip_call) ? 1 : 0;
	}
	re_thread_leave();
	return onhold;
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
	omnix_call_entry_t *entry;

	entry = omnix_find_call_by_id(call_id);
	if (!entry) {
		return OMNIX_CALL_IDLE;
	}
	return entry->info.state;
}
