/**
 * SDK-020: Mute — call_set_audio_ldir(RECVONLY/SENDRECV) inside re lock;
 * entry->info.is_muted updated. SDP_RECVONLY = local sends nothing.
 */
#include "omnix_voice/omnix_voice.h"
#include "omnix_internal.h"

#include <re.h>

#include <stdio.h>
#include <string.h>

enum { MAX_CB = 16 };

struct call_cb_rec {
	omnix_call_state_t state;
	omnix_call_info_t info;
};

static struct call_cb_rec g_cbs[MAX_CB];
static int g_cb_count;

static int fail(const char *msg)
{
	fprintf(stderr, "FAIL: %s\n", msg);
	return 1;
}

static void on_call(omnix_call_state_t state, const omnix_call_info_t *call,
		    void *ctx)
{
	(void)ctx;
	if (g_cb_count >= MAX_CB || !call) {
		return;
	}
	g_cbs[g_cb_count].state = state;
	g_cbs[g_cb_count].info = *call;
	++g_cb_count;
}

static void reset_cbs(void)
{
	memset(g_cbs, 0, sizeof(g_cbs));
	g_cb_count = 0;
}

static void fill_cfg(omnix_config_t *cfg, void *ctx)
{
	memset(cfg, 0, sizeof(*cfg));
	cfg->sip_server = "sips:sip.example.com:5061";
	cfg->sip_user = "user@example.com";
	cfg->auth_user = "authuser";
	cfg->sip_password = "test-password-NOT-A-REAL-SECRET";
	cfg->display_name = "Omnix Mute";
	cfg->verify_tls_cert = true;
	cfg->enable_srtp = true;
	cfg->on_call_event = on_call;
	cfg->ctx = ctx;
}

static int wait_cb_at_least(int n, int timeout_ms)
{
	int i;

	for (i = 0; i < timeout_ms; ++i) {
		if (g_cb_count >= n) {
			return 0;
		}
		sys_msleep(1);
	}
	return -1;
}

/** AC: unknown / empty call_id → INVALID_STATE (not NOT_SUPPORTED). */
static int test_unknown_call_id(void)
{
	omnix_config_t cfg;
	static int ctx_token = 0x2001;
	omnix_error_t err;

	reset_cbs();
	fill_cfg(&cfg, &ctx_token);

	if (omnix_init(&cfg) != OMNIX_ERR_OK) {
		return fail("omnix_init");
	}

	err = omnix_call_set_mute("no-such-call-id", true);
	if (err != OMNIX_ERR_INVALID_STATE) {
		fprintf(stderr, "mute err=%d\n", (int)err);
		omnix_shutdown();
		return fail("mute expected INVALID_STATE");
	}

	err = omnix_call_set_mute(NULL, true);
	if (err != OMNIX_ERR_INVALID_STATE) {
		omnix_shutdown();
		return fail("mute NULL expected INVALID_STATE");
	}

	err = omnix_call_set_mute("", false);
	if (err != OMNIX_ERR_INVALID_STATE) {
		omnix_shutdown();
		return fail("mute empty expected INVALID_STATE");
	}

	omnix_shutdown();
	return 0;
}

/**
 * AC: mute → call_set_audio_ldir(SDP_RECVONLY) under re lock; is_muted true;
 * unmute → SDP_SENDRECV; is_muted false. Host verifies SDP dir via helper.
 */
static int test_mute_unmute_ldir(void)
{
	omnix_config_t cfg;
	static int ctx_token = 0x2002;
	char call_id[128];
	omnix_error_t err;
	omnix_call_entry_t *entry;
	int ldir;

	reset_cbs();
	fill_cfg(&cfg, &ctx_token);

	if (omnix_init(&cfg) != OMNIX_ERR_OK) {
		return fail("omnix_init");
	}

	if (omnix_test_inject_incoming_bevent("sip:peer@127.0.0.1") != 0) {
		omnix_shutdown();
		return fail("inject incoming");
	}
	if (wait_cb_at_least(1, 3000) != 0) {
		omnix_shutdown();
		return fail("timeout INCOMING");
	}
	if (g_cbs[0].state != OMNIX_CALL_INCOMING ||
	    g_cbs[0].info.call_id[0] == '\0') {
		omnix_shutdown();
		return fail("expected tracked INCOMING");
	}

	str_ncpy(call_id, g_cbs[0].info.call_id, sizeof(call_id));

	/* Host inject never reaches SDP-offer stream alloc — ensure audio. */
	if (omnix_test_ensure_call_audio(call_id) != 0) {
		omnix_shutdown();
		return fail("ensure call audio streams");
	}

	err = omnix_call_set_mute(call_id, true);
	if (err == OMNIX_ERR_NOT_SUPPORTED) {
		omnix_shutdown();
		return fail("mute still stubbed NOT_SUPPORTED");
	}
	if (err != OMNIX_ERR_OK) {
		fprintf(stderr, "mute err=%d\n", (int)err);
		omnix_shutdown();
		return fail("mute expected OK");
	}

	entry = omnix_find_call_by_id(call_id);
	if (!entry || !entry->info.is_muted) {
		omnix_shutdown();
		return fail("is_muted should be true after mute");
	}

	ldir = omnix_test_call_audio_ldir(call_id);
	if (ldir < 0) {
		omnix_shutdown();
		return fail("audio ldir unavailable after mute");
	}
	/* SDP_RECVONLY == 1 — local sends nothing */
	if (ldir != 1) {
		fprintf(stderr, "muted ldir=%d (want SDP_RECVONLY=1)\n", ldir);
		omnix_shutdown();
		return fail("muted audio ldir must be SDP_RECVONLY");
	}

	err = omnix_call_set_mute(call_id, false);
	if (err != OMNIX_ERR_OK) {
		fprintf(stderr, "unmute err=%d\n", (int)err);
		omnix_shutdown();
		return fail("unmute expected OK");
	}

	entry = omnix_find_call_by_id(call_id);
	if (!entry || entry->info.is_muted) {
		omnix_shutdown();
		return fail("is_muted should be false after unmute");
	}

	ldir = omnix_test_call_audio_ldir(call_id);
	if (ldir < 0) {
		omnix_shutdown();
		return fail("audio ldir unavailable after unmute");
	}
	/* SDP_SENDRECV == 3 — local TX restored */
	if (ldir != 3) {
		fprintf(stderr, "unmuted ldir=%d (want SDP_SENDRECV=3)\n",
			ldir);
		omnix_shutdown();
		return fail("unmuted audio ldir must be SDP_SENDRECV");
	}

	omnix_shutdown();
	return 0;
}

int main(void)
{
	int rc = 0;

	if (test_unknown_call_id() != 0) {
		rc = 1;
	}
	if (test_mute_unmute_ldir() != 0) {
		rc = 1;
	}

	if (rc == 0) {
		printf("PASS: mute\n");
	}
	return rc;
}
