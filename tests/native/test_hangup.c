/**
 * SDK-019: Hangup — call_hangup(call, 0, NULL) inside re lock;
 * CALL_EVENT_CLOSED → ENDED/FAILED + free slot + on_call_event.
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
	cfg->display_name = "Omnix Hangup";
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

static int saw_state(omnix_call_state_t st)
{
	int i;

	for (i = 0; i < g_cb_count; ++i) {
		if (g_cbs[i].state == st) {
			return 1;
		}
	}
	return 0;
}

/** AC: unknown / empty call_id → INVALID_STATE (not NOT_SUPPORTED). */
static int test_unknown_call_id(void)
{
	omnix_config_t cfg;
	static int ctx_token = 0x1901;
	omnix_error_t err;

	reset_cbs();
	fill_cfg(&cfg, &ctx_token);

	if (omnix_init(&cfg) != OMNIX_ERR_OK) {
		return fail("omnix_init");
	}

	err = omnix_call_hangup("no-such-call-id");
	if (err != OMNIX_ERR_INVALID_STATE) {
		fprintf(stderr, "hangup err=%d\n", (int)err);
		omnix_shutdown();
		return fail("hangup expected INVALID_STATE");
	}

	err = omnix_call_hangup(NULL);
	if (err != OMNIX_ERR_INVALID_STATE) {
		omnix_shutdown();
		return fail("hangup NULL expected INVALID_STATE");
	}

	err = omnix_call_hangup("");
	if (err != OMNIX_ERR_INVALID_STATE) {
		omnix_shutdown();
		return fail("hangup empty expected INVALID_STATE");
	}

	omnix_shutdown();
	return 0;
}

/**
 * AC: hangup → call_hangup(0, NULL) under re lock; CLOSED path frees slot
 * and fires on_call_event (ENDING then ENDED on host inject).
 */
static int test_hangup_ended(void)
{
	omnix_config_t cfg;
	static int ctx_token = 0x1902;
	char call_id[128];
	omnix_error_t err;
	unsigned before;

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
	before = omnix_call_registry_count();
	if (before < 1) {
		omnix_shutdown();
		return fail("registry empty before hangup");
	}

	err = omnix_call_hangup(call_id);
	if (err == OMNIX_ERR_NOT_SUPPORTED) {
		omnix_shutdown();
		return fail("hangup still stubbed NOT_SUPPORTED");
	}
	if (err != OMNIX_ERR_OK) {
		fprintf(stderr, "hangup err=%d\n", (int)err);
		omnix_shutdown();
		return fail("hangup expected OK");
	}

	if (wait_cb_at_least(3, 3000) != 0) {
		omnix_shutdown();
		return fail("timeout ENDING/ENDED callbacks");
	}
	if (!saw_state(OMNIX_CALL_ENDING)) {
		omnix_shutdown();
		return fail("expected ENDING event");
	}
	if (!saw_state(OMNIX_CALL_ENDED)) {
		omnix_shutdown();
		return fail("expected ENDED event (scode 0)");
	}
	if (saw_state(OMNIX_CALL_FAILED)) {
		omnix_shutdown();
		return fail("local hangup must not be FAILED");
	}

	sys_msleep(50);
	if (omnix_find_call_by_id(call_id) != NULL) {
		omnix_shutdown();
		return fail("slot should be freed after hangup");
	}
	if (omnix_call_registry_count() >= before) {
		omnix_shutdown();
		return fail("registry count should drop after hangup");
	}

	omnix_shutdown();
	return 0;
}

/**
 * AC: CLOSED with non-zero SIP code → FAILED + free slot + on_call_event.
 */
static int test_closed_failed_sip_code(void)
{
	omnix_config_t cfg;
	static int ctx_token = 0x1903;
	char call_id[128];
	int n_before;

	reset_cbs();
	fill_cfg(&cfg, &ctx_token);

	if (omnix_init(&cfg) != OMNIX_ERR_OK) {
		return fail("omnix_init");
	}

	if (omnix_test_inject_incoming_bevent("sip:fail@127.0.0.1") != 0) {
		omnix_shutdown();
		return fail("inject incoming");
	}
	if (wait_cb_at_least(1, 3000) != 0) {
		omnix_shutdown();
		return fail("timeout INCOMING");
	}

	str_ncpy(call_id, g_cbs[0].info.call_id, sizeof(call_id));
	n_before = g_cb_count;

	if (omnix_test_inject_call_closed(call_id, "486 Busy Here") != 0) {
		omnix_shutdown();
		return fail("inject CLOSED 486");
	}

	if (wait_cb_at_least(n_before + 1, 3000) != 0) {
		omnix_shutdown();
		return fail("timeout FAILED callback");
	}
	if (!saw_state(OMNIX_CALL_FAILED)) {
		omnix_shutdown();
		return fail("expected FAILED for SIP 486 CLOSED");
	}

	sys_msleep(50);
	if (omnix_find_call_by_id(call_id) != NULL) {
		omnix_shutdown();
		return fail("slot should be freed after FAILED CLOSED");
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
	if (test_hangup_ended() != 0) {
		rc = 1;
	}
	if (test_closed_failed_sip_code() != 0) {
		rc = 1;
	}

	if (rc == 0) {
		printf("PASS: hangup\n");
	}
	return rc;
}
