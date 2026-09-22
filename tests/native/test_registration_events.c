/**
 * SDK-014: Registration events — complete UA bevent → omnix_reg_state_t map.
 *
 * Baresip 4.11 events exercised:
 *   REGISTERING, REGISTER_OK, REGISTER_FAIL, UNREGISTERING
 * Conceptual UNREGISTERED (no BEVENT_UNREGISTERED) is delivered as
 * OMNIX_REG_UNREGISTERED from UNREGISTERING and from expire=0 REGISTER_OK
 * while unregister_pending.
 */
#include "omnix_voice/omnix_voice.h"
#include "omnix_internal.h"

#include <re.h>
#include <stdio.h>
#include <string.h>

enum { MAX_CB = 16 };

struct reg_cb_rec {
	omnix_reg_state_t state;
	int sip_code;
	char reason[160];
};

static struct reg_cb_rec g_cbs[MAX_CB];
static int g_cb_count;
static void *g_cb_ctx_seen;

static int fail(const char *msg)
{
	fprintf(stderr, "FAIL: %s\n", msg);
	return 1;
}

static void on_reg(omnix_reg_state_t state, int sip_code, const char *reason,
		   void *ctx)
{
	if (g_cb_count >= MAX_CB) {
		return;
	}
	g_cbs[g_cb_count].state = state;
	g_cbs[g_cb_count].sip_code = sip_code;
	if (reason) {
		str_ncpy(g_cbs[g_cb_count].reason, reason,
			 sizeof(g_cbs[g_cb_count].reason));
	}
	else {
		g_cbs[g_cb_count].reason[0] = '\0';
	}
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
	cfg->display_name = "Omnix Reg Events";
	cfg->verify_tls_cert = true;
	cfg->enable_srtp = true;
	cfg->on_reg_state = on_reg;
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

static int wait_state(omnix_reg_state_t want, int timeout_ms)
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

static int expect_cb(omnix_reg_state_t state, int sip_code, const char *reason,
		     void *ctx, const char *label)
{
	if (wait_cb_at_least(1, 2000) != 0) {
		return fail(label);
	}
	if (g_cbs[0].state != state) {
		fprintf(stderr, "%s: state=%d want=%d\n", label,
			(int)g_cbs[0].state, (int)state);
		return fail(label);
	}
	if (g_cbs[0].sip_code != sip_code) {
		fprintf(stderr, "%s: code=%d want=%d\n", label,
			g_cbs[0].sip_code, sip_code);
		return fail(label);
	}
	if (reason) {
		if (strcmp(g_cbs[0].reason, reason) != 0) {
			fprintf(stderr, "%s: reason='%s' want='%s'\n", label,
				g_cbs[0].reason, reason);
			return fail(label);
		}
	}
	if (g_cb_ctx_seen != ctx) {
		return fail(label);
	}
	return 0;
}

/** AC: native test for initial state UNINITIALIZED. */
static int test_initial_uninitialized(void)
{
	if (omnix_get_reg_state() != OMNIX_REG_UNINITIALIZED) {
		return fail("expected UNINITIALIZED before init");
	}
	return 0;
}

/**
 * All 5 registration events → omnix_reg_state_t, with callback params.
 * Uses inject only (no network race).
 */
static int test_all_five_events(void)
{
	omnix_config_t cfg;
	static int ctx_token = 0x514;
	struct omnix_state *st;

	reset_cbs();
	fill_cfg(&cfg, &ctx_token);

	if (omnix_init(&cfg) != OMNIX_ERR_OK) {
		return fail("omnix_init");
	}

	if (omnix_get_reg_state() != OMNIX_REG_UNREGISTERED) {
		omnix_shutdown();
		return fail("expected UNREGISTERED after init");
	}

	/* 1) REGISTERING → OMNIX_REG_REGISTERING */
	reset_cbs();
	if (omnix_test_inject_reg_bevent(3, NULL) != 0) {
		omnix_shutdown();
		return fail("inject REGISTERING");
	}
	if (wait_state(OMNIX_REG_REGISTERING, 2000) != 0) {
		omnix_shutdown();
		return fail("state after REGISTERING");
	}
	if (expect_cb(OMNIX_REG_REGISTERING, 0, NULL, &ctx_token,
		      "REGISTERING callback") != 0) {
		omnix_shutdown();
		return 1;
	}

	/* 2) REGISTER_OK → OMNIX_REG_REGISTERED (+ sip_code/reason/ctx) */
	reset_cbs();
	if (omnix_test_inject_reg_bevent(0, "200 OK") != 0) {
		omnix_shutdown();
		return fail("inject REGISTER_OK");
	}
	if (wait_state(OMNIX_REG_REGISTERED, 2000) != 0) {
		omnix_shutdown();
		return fail("state after REGISTER_OK");
	}
	if (expect_cb(OMNIX_REG_REGISTERED, 200, "OK", &ctx_token,
		      "REGISTER_OK callback") != 0) {
		omnix_shutdown();
		return 1;
	}

	/* 3) REGISTER_FAIL → OMNIX_REG_FAILED */
	reset_cbs();
	if (omnix_test_inject_reg_bevent(1, "403 Forbidden") != 0) {
		omnix_shutdown();
		return fail("inject REGISTER_FAIL");
	}
	if (wait_state(OMNIX_REG_FAILED, 2000) != 0) {
		omnix_shutdown();
		return fail("state after REGISTER_FAIL");
	}
	if (expect_cb(OMNIX_REG_FAILED, 403, "Forbidden", &ctx_token,
		      "REGISTER_FAIL callback") != 0) {
		omnix_shutdown();
		return 1;
	}

	/* 4) UNREGISTERING → OMNIX_REG_UNREGISTERED (Baresip has no
	 *    BEVENT_UNREGISTERED; this is the UA counterpart). */
	reset_cbs();
	if (omnix_test_inject_reg_bevent(2, NULL) != 0) {
		omnix_shutdown();
		return fail("inject UNREGISTERING");
	}
	if (wait_state(OMNIX_REG_UNREGISTERED, 2000) != 0) {
		omnix_shutdown();
		return fail("state after UNREGISTERING");
	}
	if (expect_cb(OMNIX_REG_UNREGISTERED, 0, NULL, &ctx_token,
		      "UNREGISTERING→UNREGISTERED callback") != 0) {
		omnix_shutdown();
		return 1;
	}

	/* 5) UNREGISTERED via expire=0 REGISTER_OK while unregister_pending.
	 *    Simulate pending without relying on network UNREGISTERING race. */
	reset_cbs();
	st = omnix_state_get();
	if (!st) {
		omnix_shutdown();
		return fail("omnix_state_get");
	}
	st->unregister_pending = true;
	st->reg_state = OMNIX_REG_REGISTERED;
	if (omnix_test_inject_reg_bevent(0, "200 OK") != 0) {
		omnix_shutdown();
		return fail("inject REGISTER_OK (unregister path)");
	}
	if (wait_state(OMNIX_REG_UNREGISTERED, 2000) != 0) {
		omnix_shutdown();
		return fail("state after UNREGISTERED (expire=0 OK)");
	}
	if (expect_cb(OMNIX_REG_UNREGISTERED, 200, "OK", &ctx_token,
		      "UNREGISTERED callback") != 0) {
		omnix_shutdown();
		return 1;
	}

	omnix_shutdown();

	if (omnix_get_reg_state() != OMNIX_REG_UNINITIALIZED) {
		return fail("expected UNINITIALIZED after shutdown");
	}

	return 0;
}

int main(void)
{
	if (test_initial_uninitialized() != 0) {
		return 1;
	}
	if (test_all_five_events() != 0) {
		return 1;
	}

	fprintf(stderr, "PASS: registration_events\n");
	return 0;
}
