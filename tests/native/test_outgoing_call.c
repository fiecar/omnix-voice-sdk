/**
 * SDK-016: Outgoing call — omnix_call_make via ua_connect,
 * NOT_REGISTERED gate, OUTGOING → on_call_event via mqueue.
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
static void *g_cb_ctx_seen;

static int fail(const char *msg)
{
	fprintf(stderr, "FAIL: %s\n", msg);
	return 1;
}

static void on_call(omnix_call_state_t state, const omnix_call_info_t *call,
		    void *ctx)
{
	if (g_cb_count >= MAX_CB || !call) {
		return;
	}
	g_cbs[g_cb_count].state = state;
	g_cbs[g_cb_count].info = *call;
	g_cb_ctx_seen = ctx;
	++g_cb_count;
}

static void reset_cbs(void)
{
	memset(g_cbs, 0, sizeof(g_cbs));
	g_cb_count = 0;
	g_cb_ctx_seen = NULL;
}

static void fill_cfg(omnix_config_t *cfg, void *ctx)
{
	memset(cfg, 0, sizeof(*cfg));
	cfg->sip_server = "sips:sip.example.com:5061";
	cfg->sip_user = "user@example.com";
	cfg->auth_user = "authuser";
	cfg->sip_password = "test-password-NOT-A-REAL-SECRET";
	cfg->display_name = "Omnix Outgoing Call";
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

static int wait_reg_state(omnix_reg_state_t want, int timeout_ms)
{
	int i;

	for (i = 0; i < timeout_ms; ++i) {
		if (omnix_get_reg_state() == want) {
			return 0;
		}
		sys_msleep(1);
	}
	return -1;
}

/** AC: Returns OMNIX_ERR_NOT_REGISTERED if not registered. */
static int test_not_registered(void)
{
	omnix_config_t cfg;
	static int ctx_token = 0x1601;
	char call_id[128];
	omnix_error_t err;

	reset_cbs();
	fill_cfg(&cfg, &ctx_token);

	if (omnix_init(&cfg) != OMNIX_ERR_OK) {
		return fail("omnix_init");
	}
	if (omnix_get_reg_state() != OMNIX_REG_UNREGISTERED) {
		omnix_shutdown();
		return fail("expected UNREGISTERED");
	}

	err = omnix_call_make("sip:peer@example.com", call_id, sizeof(call_id));
	if (err != OMNIX_ERR_NOT_REGISTERED) {
		fprintf(stderr, "err=%d\n", (int)err);
		omnix_shutdown();
		return fail("expected NOT_REGISTERED");
	}
	if (call_id[0] != '\0') {
		omnix_shutdown();
		return fail("call_id should be empty on NOT_REGISTERED");
	}
	if (g_cb_count != 0) {
		omnix_shutdown();
		return fail("no call callback when not registered");
	}

	omnix_shutdown();
	return 0;
}

/**
 * AC: ua_connect inside re lock; OUTGOING fires on_call_event.
 * REGISTERED via inject (no real SIP server). Destination uses literal IP
 * so invite can be attempted without DNS.
 */
static int test_outgoing_make_and_event(void)
{
	omnix_config_t cfg;
	static int ctx_token = 0x1602;
	char call_id[128];
	omnix_error_t err;
	omnix_call_entry_t *entry;
	const char *dest = "sip:peer@127.0.0.1";

	reset_cbs();
	fill_cfg(&cfg, &ctx_token);

	if (omnix_init(&cfg) != OMNIX_ERR_OK) {
		return fail("omnix_init");
	}

	/* REGISTERED without a live SIP server (same inject pattern as SDK-013). */
	if (omnix_test_inject_reg_bevent(0, "200 OK") != 0) {
		omnix_shutdown();
		return fail("inject REGISTER_OK");
	}
	if (wait_reg_state(OMNIX_REG_REGISTERED, 3000) != 0) {
		omnix_shutdown();
		return fail("not REGISTERED after inject");
	}

	err = omnix_call_make(dest, call_id, sizeof(call_id));
	if (err != OMNIX_ERR_OK) {
		fprintf(stderr, "omnix_call_make err=%d\n", (int)err);
		omnix_shutdown();
		return fail("omnix_call_make");
	}
	if (call_id[0] == '\0') {
		omnix_shutdown();
		return fail("empty call_id");
	}

	if (wait_cb_at_least(1, 3000) != 0) {
		omnix_shutdown();
		return fail("timeout waiting for on_call_event");
	}

	if (g_cbs[0].state != OMNIX_CALL_OUTGOING) {
		fprintf(stderr, "state=%d\n", (int)g_cbs[0].state);
		omnix_shutdown();
		return fail("expected OMNIX_CALL_OUTGOING");
	}
	if (g_cb_ctx_seen != &ctx_token) {
		omnix_shutdown();
		return fail("callback ctx mismatch");
	}
	if (strcmp(g_cbs[0].info.call_id, call_id) != 0) {
		omnix_shutdown();
		return fail("callback call_id mismatch");
	}
	if (!g_cbs[0].info.is_outgoing) {
		omnix_shutdown();
		return fail("expected is_outgoing");
	}

	entry = omnix_find_call_by_id(call_id);
	if (!entry) {
		omnix_shutdown();
		return fail("call not in registry");
	}
	if (omnix_call_get_state(call_id) != OMNIX_CALL_OUTGOING) {
		omnix_shutdown();
		return fail("get_state != OUTGOING");
	}

	omnix_shutdown();
	return 0;
}

int main(void)
{
	int rc = 0;

	if (test_not_registered() != 0) {
		rc = 1;
	}
	if (test_outgoing_make_and_event() != 0) {
		rc = 1;
	}

	if (rc == 0) {
		printf("PASS: outgoing_call\n");
	}
	return rc;
}
