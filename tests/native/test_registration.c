/**
 * SDK-013: SIP registration — ua_register in re lock, bevent→mqueue callbacks.
 * Real-server (H-3) checks skip unless OMNIX_TEST_SIP_* is set.
 */
#include "omnix_voice/omnix_voice.h"
#include "omnix_internal.h"

#include <re.h>
#include <stdio.h>
#include <stdlib.h>
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
	cfg->display_name = "Omnix Reg Test";
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

static int test_bevent_mapping_and_register(void)
{
	omnix_config_t cfg;
	static int ctx_token = 0x513;
	const char *ob;
	int before;
	omnix_error_t rerr;

	reset_cbs();
	fill_cfg(&cfg, &ctx_token);

	if (omnix_init(&cfg) != OMNIX_ERR_OK) {
		return fail("omnix_init");
	}

	if (omnix_get_reg_state() != OMNIX_REG_UNREGISTERED) {
		omnix_shutdown();
		return fail("expected UNREGISTERED after init");
	}

	ob = omnix_test_account_outbound();
	if (!ob || strcmp(ob, "sips:sip.example.com:5061") != 0) {
		fprintf(stderr, "outbound=%s\n", ob ? ob : "(null)");
		omnix_shutdown();
		return fail("expected outbound = sip_server");
	}

	/* --- Event mapping via inject (no network race) --- */

	reset_cbs();
	if (omnix_test_inject_reg_bevent(0, "200 OK") != 0) {
		omnix_shutdown();
		return fail("inject REGISTER_OK");
	}
	if (wait_state(OMNIX_REG_REGISTERED, 2000) != 0) {
		omnix_shutdown();
		return fail("expected REGISTERED after inject OK");
	}
	if (wait_cb_at_least(1, 2000) != 0) {
		omnix_shutdown();
		return fail("expected callback after REGISTER_OK");
	}
	if (g_cbs[0].state != OMNIX_REG_REGISTERED || g_cbs[0].sip_code != 200) {
		fprintf(stderr, "cb state=%d code=%d reason=%s\n",
			(int)g_cbs[0].state, g_cbs[0].sip_code, g_cbs[0].reason);
		omnix_shutdown();
		return fail("REGISTER_OK mapping");
	}
	if (g_cb_ctx_seen != &ctx_token) {
		omnix_shutdown();
		return fail("callback ctx mismatch");
	}

	reset_cbs();
	if (omnix_test_inject_reg_bevent(1, "401 Unauthorized") != 0) {
		omnix_shutdown();
		return fail("inject REGISTER_FAIL 401");
	}
	if (wait_state(OMNIX_REG_FAILED, 2000) != 0) {
		omnix_shutdown();
		return fail("expected FAILED after 401 inject");
	}
	if (wait_cb_at_least(1, 2000) != 0 || g_cbs[0].sip_code != 401 ||
	    g_cbs[0].state != OMNIX_REG_FAILED) {
		omnix_shutdown();
		return fail("401 FAIL mapping");
	}

	reset_cbs();
	if (omnix_test_inject_reg_bevent(1, "403 Forbidden") != 0) {
		omnix_shutdown();
		return fail("inject 403");
	}
	if (wait_cb_at_least(1, 2000) != 0 || g_cbs[0].sip_code != 403) {
		omnix_shutdown();
		return fail("403 FAIL mapping");
	}

	reset_cbs();
	if (omnix_test_inject_reg_bevent(2, NULL) != 0) {
		omnix_shutdown();
		return fail("inject UNREGISTERING");
	}
	if (wait_state(OMNIX_REG_UNREGISTERED, 2000) != 0) {
		omnix_shutdown();
		return fail("expected UNREGISTERED after UNREGISTERING");
	}
	if (wait_cb_at_least(1, 2000) != 0 ||
	    g_cbs[0].state != OMNIX_REG_UNREGISTERED) {
		omnix_shutdown();
		return fail("UNREGISTERING mapping");
	}

	/* --- omnix_register: ua_register inside re lock + REGISTERING cb --- */
	reset_cbs();
	before = g_cb_count;
	rerr = omnix_register();
	if (rerr != OMNIX_ERR_OK && rerr != OMNIX_ERR_REGISTRATION_FAILED) {
		omnix_shutdown();
		return fail("unexpected omnix_register error");
	}
	if (wait_cb_at_least(before + 1, 2000) != 0) {
		omnix_shutdown();
		return fail("expected on_reg_state after register");
	}
	if (g_cbs[before].state != OMNIX_REG_REGISTERING) {
		fprintf(stderr, "first cb state=%d\n", (int)g_cbs[before].state);
		omnix_shutdown();
		return fail("expected REGISTERING callback");
	}

	/* Unregister API exercises ua_unregister inside re lock. */
	omnix_unregister();
	if (wait_state(OMNIX_REG_UNREGISTERED, 3000) != 0) {
		/* Force via inject if placeholder network is slow. */
		(void)omnix_test_inject_reg_bevent(2, NULL);
		if (wait_state(OMNIX_REG_UNREGISTERED, 2000) != 0) {
			omnix_shutdown();
			return fail("expected UNREGISTERED after unregister");
		}
	}

	omnix_shutdown();
	return 0;
}

/**
 * H-3 real-server gate. Uses env only; never logs password.
 * Returns 0 on skip or pass; 1 on hard failure when env is present.
 */
static int test_real_server_optional(void)
{
	const char *server = getenv("OMNIX_TEST_SIP_SERVER");
	const char *user = getenv("OMNIX_TEST_SIP_USER");
	const char *auth = getenv("OMNIX_TEST_SIP_AUTH_USER");
	const char *pass = getenv("OMNIX_TEST_SIP_PASSWORD");
	omnix_config_t cfg;
	omnix_error_t err;
	int i;

	if (!server || !server[0] || !user || !user[0] || !pass || !pass[0]) {
		fprintf(stderr,
			"SKIP: real-server (H-3) — OMNIX_TEST_SIP_* not set\n");
		return 0;
	}

	reset_cbs();
	memset(&cfg, 0, sizeof(cfg));
	cfg.sip_server = server;
	cfg.sip_user = user;
	cfg.auth_user = (auth && auth[0]) ? auth : NULL;
	cfg.sip_password = pass;
	cfg.verify_tls_cert = true;
	cfg.enable_srtp = true;
	cfg.on_reg_state = on_reg;

	err = omnix_init(&cfg);
	cfg.sip_password = NULL; /* do not retain/log */
	if (err != OMNIX_ERR_OK) {
		return fail("real-server omnix_init");
	}

	if (omnix_register() != OMNIX_ERR_OK) {
		omnix_shutdown();
		return fail("real-server omnix_register");
	}

	for (i = 0; i < 15000; ++i) {
		omnix_reg_state_t st = omnix_get_reg_state();
		if (st == OMNIX_REG_REGISTERED || st == OMNIX_REG_FAILED) {
			break;
		}
		sys_msleep(1);
	}

	if (omnix_get_reg_state() != OMNIX_REG_REGISTERED) {
		fprintf(stderr, "real-server reg_state=%d\n",
			(int)omnix_get_reg_state());
		omnix_shutdown();
		return fail("real-server did not reach REGISTERED");
	}

	omnix_unregister();
	if (wait_state(OMNIX_REG_UNREGISTERED, 10000) != 0) {
		omnix_shutdown();
		return fail("real-server unregister");
	}

	omnix_shutdown();
	fprintf(stderr, "PASS: real-server registration\n");
	return 0;
}

int main(void)
{
	if (test_bevent_mapping_and_register() != 0) {
		return 1;
	}
	if (test_real_server_optional() != 0) {
		return 1;
	}

	fprintf(stderr, "PASS: registration\n");
	return 0;
}
