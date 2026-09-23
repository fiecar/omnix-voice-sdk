/**
 * SDK-022: DTMF — digit validation (0-9, star, hash, A-D) + call_send_digit
 * under re lock. Host proves validation + send path; SIP-server reception
 * is gate H-3 / SDK-065 (not invented PASS here).
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
	cfg->display_name = "Omnix DTMF";
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

/** AC: invalid chars rejected → INVALID_CONFIG (not NOT_SUPPORTED). */
static int test_invalid_digits(void)
{
	omnix_config_t cfg;
	static int ctx_token = 0x2201;
	omnix_error_t err;
	char call_id[128];
	const char *bad = "XxEeGg!@ $";
	size_t i;

	reset_cbs();
	omnix_test_reset_last_dtmf();
	fill_cfg(&cfg, &ctx_token);

	if (omnix_init(&cfg) != OMNIX_ERR_OK) {
		return fail("omnix_init");
	}

	err = omnix_call_send_dtmf("no-such-call-id", '5');
	if (err != OMNIX_ERR_INVALID_STATE) {
		fprintf(stderr, "unknown call err=%d\n", (int)err);
		omnix_shutdown();
		return fail("unknown call expected INVALID_STATE");
	}

	err = omnix_call_send_dtmf(NULL, '5');
	if (err != OMNIX_ERR_INVALID_STATE) {
		omnix_shutdown();
		return fail("NULL call_id expected INVALID_STATE");
	}

	err = omnix_call_send_dtmf("", '5');
	if (err != OMNIX_ERR_INVALID_STATE) {
		omnix_shutdown();
		return fail("empty call_id expected INVALID_STATE");
	}

	if (omnix_test_inject_incoming_bevent("sip:peer@127.0.0.1") != 0) {
		omnix_shutdown();
		return fail("inject incoming");
	}
	if (wait_cb_at_least(1, 3000) != 0) {
		omnix_shutdown();
		return fail("timeout INCOMING");
	}
	str_ncpy(call_id, g_cbs[0].info.call_id, sizeof(call_id));

	for (i = 0; bad[i] != '\0'; ++i) {
		err = omnix_call_send_dtmf(call_id, bad[i]);
		if (err == OMNIX_ERR_NOT_SUPPORTED) {
			omnix_shutdown();
			return fail("dtmf still stubbed NOT_SUPPORTED");
		}
		if (err != OMNIX_ERR_INVALID_CONFIG) {
			fprintf(stderr, "bad digit '%c' (0x%02x) err=%d\n",
				bad[i], (unsigned)(unsigned char)bad[i],
				(int)err);
			omnix_shutdown();
			return fail("invalid digit expected INVALID_CONFIG");
		}
	}

	if (omnix_test_last_dtmf_digit() != 0) {
		omnix_shutdown();
		return fail("last dtmf must stay unset after rejects");
	}

	omnix_shutdown();
	return 0;
}

/**
 * AC: valid digits → call_send_digit under re lock → OK; helper records digit.
 * Full alphabet 0-9 * # A-D (and a-d alias).
 */
static int test_valid_digits_send(void)
{
	omnix_config_t cfg;
	static int ctx_token = 0x2202;
	char call_id[128];
	omnix_error_t err;
	const char *good = "0123456789*#ABCDabcd";
	size_t i;

	reset_cbs();
	omnix_test_reset_last_dtmf();
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
	if (g_cbs[0].info.call_id[0] == '\0') {
		omnix_shutdown();
		return fail("expected tracked call_id");
	}
	str_ncpy(call_id, g_cbs[0].info.call_id, sizeof(call_id));

	if (omnix_test_ensure_call_audio(call_id) != 0) {
		omnix_shutdown();
		return fail("ensure call audio streams");
	}

	for (i = 0; good[i] != '\0'; ++i) {
		omnix_test_reset_last_dtmf();
		err = omnix_call_send_dtmf(call_id, good[i]);
		if (err == OMNIX_ERR_NOT_SUPPORTED) {
			omnix_shutdown();
			return fail("dtmf still stubbed NOT_SUPPORTED");
		}
		if (err != OMNIX_ERR_OK) {
			fprintf(stderr, "digit '%c' err=%d\n", good[i],
				(int)err);
			omnix_shutdown();
			return fail("valid digit expected OK");
		}
		if (omnix_test_last_dtmf_digit() != good[i]) {
			fprintf(stderr, "last digit='%c' want='%c'\n",
				omnix_test_last_dtmf_digit(), good[i]);
			omnix_shutdown();
			return fail("last dtmf digit not recorded");
		}
	}

	omnix_shutdown();
	return 0;
}

int main(void)
{
	int rc = 0;

	if (test_invalid_digits() != 0) {
		rc = 1;
	}
	if (test_valid_digits_send() != 0) {
		rc = 1;
	}

	if (rc == 0) {
		printf("PASS: dtmf\n");
	}
	return rc;
}
