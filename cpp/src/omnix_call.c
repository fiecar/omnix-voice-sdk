/**
 * Omnix Voice — call registry (SDK-015) + call control stubs (SDK-010).
 *
 * Tracks active calls by call_id. struct call * stays internal only.
 * Slot helpers are intended for use under the re thread lock (SDK-016+).
 */
#include "omnix_internal.h"

#include <re.h>
#include <baresip.h>

#include <string.h>

#define OMNIX_MAX_CALLS 8

static omnix_call_entry_t g_calls[OMNIX_MAX_CALLS];

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
	omnix_call_entry_t *entry;

	entry = omnix_find_call_by_id(call_id);
	if (!entry) {
		return OMNIX_CALL_IDLE;
	}
	return entry->info.state;
}
