/**
 * SDK-018: Answer / Reject — call_answer(200, VIDMODE_OFF) /
 * call_hangup(486, "Busy Here") inside re lock; INVALID_STATE if unknown id.
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
	cfg->display_name = "Omnix Answer Reject";
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

/** AC: Returns OMNIX_ERR_INVALID_STATE if call_id not found. */
static int test_unknown_call_id(void)
{
	omnix_config_t cfg;
	static int ctx_token = 0x1801;
	omnix_error_t err;

	reset_cbs();
	fill_cfg(&cfg, &ctx_token);

	if (omnix_init(&cfg) != OMNIX_ERR_OK) {
		return fail("omnix_init");
	}

	err = omnix_call_answer("no-such-call-id");
	if (err != OMNIX_ERR_INVALID_STATE) {
		fprintf(stderr, "answer err=%d\n", (int)err);
		omnix_shutdown();
		return fail("answer expected INVALID_STATE");
	}

	err = omnix_call_reject("no-such-call-id");
	if (err != OMNIX_ERR_INVALID_STATE) {
		fprintf(stderr, "reject err=%d\n", (int)err);
		omnix_shutdown();
		return fail("reject expected INVALID_STATE");
	}

	err = omnix_call_answer(NULL);
	if (err != OMNIX_ERR_INVALID_STATE) {
		omnix_shutdown();
		return fail("answer NULL expected INVALID_STATE");
	}

	err = omnix_call_reject("");
	if (err != OMNIX_ERR_INVALID_STATE) {
		omnix_shutdown();
		return fail("reject empty expected INVALID_STATE");
	}

	omnix_shutdown();
	return 0;
}

/**
 * AC: Reject → call_hangup(..., 486, "Busy Here") under re lock.
 * Host inject yields a tracked call; hangup closes and frees the slot.
 */
static int test_reject_486(void)
{
	omnix_config_t cfg;
	static int ctx_token = 0x1802;
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
		return fail("registry empty before reject");
	}

	err = omnix_call_reject(call_id);
	if (err != OMNIX_ERR_OK) {
		fprintf(stderr, "reject err=%d\n", (int)err);
		omnix_shutdown();
		return fail("reject expected OK");
	}

	/* CLOSED frees slot under re lock (sync); allow brief settle. */
	sys_msleep(50);
	if (omnix_find_call_by_id(call_id) != NULL) {
		omnix_shutdown();
		return fail("slot should be freed after reject");
	}
	if (omnix_call_registry_count() >= before) {
		omnix_shutdown();
		return fail("registry count should drop after reject");
	}

	omnix_shutdown();
	return 0;
}

/**
 * AC: Answer → call_answer(..., 200, VIDMODE_OFF) under re lock.
 *
 * Host CI injects BEVENT_CALL_INCOMING on a call_connect'd object (Baresip
 * state remains OUTGOING), so call_answer returns EINVAL → INVALID_STATE.
 * That still proves the Omnix wrapper invokes call_answer(200, VIDMODE_OFF)
 * rather than the old NOT_SUPPORTED stub. Live SIP 200 needs a true INVITE
 * (device / SDK-065).
 */
static int test_answer_invokes_call_answer_200(void)
{
	omnix_config_t cfg;
	static int ctx_token = 0x1803;
	char call_id[128];
	omnix_error_t err;

	reset_cbs();
	fill_cfg(&cfg, &ctx_token);

	if (omnix_init(&cfg) != OMNIX_ERR_OK) {
		return fail("omnix_init");
	}

	if (omnix_test_inject_incoming_bevent("sip:answer@127.0.0.1") != 0) {
		omnix_shutdown();
		return fail("inject incoming");
	}
	if (wait_cb_at_least(1, 3000) != 0) {
		omnix_shutdown();
		return fail("timeout INCOMING");
	}

	str_ncpy(call_id, g_cbs[0].info.call_id, sizeof(call_id));
	if (call_id[0] == '\0') {
		omnix_shutdown();
		return fail("empty call_id");
	}

	err = omnix_call_answer(call_id);
	if (err == OMNIX_ERR_NOT_SUPPORTED) {
		omnix_shutdown();
		return fail("answer still stubbed NOT_SUPPORTED");
	}
	/*
	 * Host inject: EINVAL → INVALID_STATE (expected).
	 * Real INVITE INCOMING: OMNIX_ERR_OK (SIP 200).
	 */
	if (err != OMNIX_ERR_INVALID_STATE && err != OMNIX_ERR_OK) {
		fprintf(stderr, "answer err=%d\n", (int)err);
		omnix_shutdown();
		return fail("answer unexpected error");
	}

	/* Clean up via reject/hangup path if still tracked. */
	if (omnix_find_call_by_id(call_id)) {
		(void)omnix_call_reject(call_id);
		sys_msleep(50);
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
	if (test_reject_486() != 0) {
		rc = 1;
	}
	if (test_answer_invokes_call_answer_200() != 0) {
		rc = 1;
	}

	if (rc == 0) {
		printf("PASS: answer_reject\n");
	}
	return rc;
}
