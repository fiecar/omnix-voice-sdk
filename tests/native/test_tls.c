/**
 * SDK-025: TLS — TLS-only SIP, verify_tls_cert default/wiring, warning when
 * false, OpenSSL version evidence, bad-cert → OMNIX_REG_FAILED.
 * Host has no live TLS peer; cert-failure path uses bevent inject (same
 * offline pattern as SDK-013). Live bad-cert against a real SIP peer is
 * gate H-3 / SDK-065 — not invented PASS here.
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

static int fail(const char *msg)
{
	fprintf(stderr, "FAIL: %s\n", msg);
	return 1;
}

static void on_reg(omnix_reg_state_t state, int sip_code, const char *reason,
		   void *ctx)
{
	(void)ctx;
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
	++g_cb_count;
}

static void reset_cbs(void)
{
	memset(g_cbs, 0, sizeof(g_cbs));
	g_cb_count = 0;
}

static void fill_cfg(omnix_config_t *cfg, bool verify)
{
	memset(cfg, 0, sizeof(*cfg));
	cfg->sip_server = "sips:sip.example.com:5061";
	cfg->sip_user = "user@example.com";
	cfg->auth_user = "authuser";
	cfg->sip_password = "test-password-NOT-A-REAL-SECRET";
	cfg->display_name = "Omnix TLS Test";
	cfg->verify_tls_cert = verify;
	cfg->enable_srtp = true;
	cfg->on_reg_state = on_reg;
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

static int test_tls_defaults_and_transport(void)
{
	omnix_config_t cfg;
	const char *aor;
	const char *ver;

	reset_cbs();
	fill_cfg(&cfg, true);

	if (omnix_init(&cfg) != OMNIX_ERR_OK) {
		return fail("omnix_init verify=true");
	}

	if (omnix_test_sip_tls_only() != 1) {
		omnix_shutdown();
		return fail("expected TLS-only sip.transports / transp");
	}
	if (omnix_test_sip_verify_server() != 1) {
		omnix_shutdown();
		return fail("expected sip.verify_server=true");
	}

	aor = omnix_test_account_aor_built();
	if (!aor || strstr(aor, "transport=tls") == NULL) {
		fprintf(stderr, "aor=%s\n", aor ? aor : "(null)");
		omnix_shutdown();
		return fail("AOR missing transport=tls");
	}

	ver = omnix_test_openssl_version();
	if (!ver || !ver[0]) {
		omnix_shutdown();
		return fail("OpenSSL version string empty");
	}
	fprintf(stderr, "OpenSSL_version: %s\n", ver);
	/*
	 * Host CI links system libssl (often 3.0.x on Ubuntu). Android/iOS
	 * MUST use SDK-066 pinned 3.5.x (CMake OPENSSL_VERSION / OMNIX_OPENSSL_ROOT).
	 * Require OpenSSL 3.x here; record full string for the Task Report.
	 */
	if (strstr(ver, "OpenSSL 3.") == NULL) {
		omnix_shutdown();
		return fail("expected OpenSSL 3.x (SDK-025 / F-13)");
	}

	omnix_shutdown();
	return 0;
}

static int test_verify_false_warning(void)
{
	omnix_config_t cfg;
	const char *log;

	reset_cbs();
	fill_cfg(&cfg, false);
	omnix_test_reset_last_log();

	if (omnix_init(&cfg) != OMNIX_ERR_OK) {
		return fail("omnix_init verify=false");
	}

	if (omnix_test_sip_verify_server() != 0) {
		omnix_shutdown();
		return fail("expected sip.verify_server=false");
	}

	if (omnix_test_warned_verify_tls_off() != 1) {
		omnix_shutdown();
		return fail("expected verify_tls_cert=false WARNING sticky");
	}

	log = omnix_test_last_log();
	/* last_log may be overwritten by later init logs; sticky is authoritative. */
	if (log && strstr(log, "verify_tls_cert=false") != NULL) {
		fprintf(stderr, "last_log still has warning: ok\n");
	}

	omnix_shutdown();
	return 0;
}

/**
 * Bad TLS cert + verify_tls_cert=true → OMNIX_REG_FAILED.
 * Host has no TLS peer; inject REGISTER_FAIL with TLS cert failure text
 * (baresip surfaces TLS verify failures as register fail). Live peer check
 * remains H-3 / SDK-065.
 */
static int test_bad_cert_reg_failed(void)
{
	omnix_config_t cfg;

	reset_cbs();
	fill_cfg(&cfg, true);

	if (omnix_init(&cfg) != OMNIX_ERR_OK) {
		return fail("omnix_init for bad-cert path");
	}

	if (omnix_test_sip_verify_server() != 1) {
		omnix_shutdown();
		return fail("verify must stay true for bad-cert test");
	}

	if (omnix_test_inject_reg_bevent(
		    1, "TLS certificate verification failed") != 0) {
		omnix_shutdown();
		return fail("inject REGISTER_FAIL TLS cert");
	}

	if (wait_state(OMNIX_REG_FAILED, 2000) != 0) {
		omnix_shutdown();
		return fail("expected OMNIX_REG_FAILED after bad TLS cert");
	}
	if (wait_cb_at_least(1, 2000) != 0 ||
	    g_cbs[0].state != OMNIX_REG_FAILED) {
		omnix_shutdown();
		return fail("expected on_reg_state OMNIX_REG_FAILED");
	}
	if (strstr(g_cbs[0].reason, "TLS") == NULL &&
	    strstr(g_cbs[0].reason, "certificate") == NULL) {
		fprintf(stderr, "reason=%s\n", g_cbs[0].reason);
		omnix_shutdown();
		return fail("expected TLS/certificate reason in callback");
	}

	omnix_shutdown();
	return 0;
}

int main(void)
{
	if (test_tls_defaults_and_transport() != 0) {
		return 1;
	}
	if (test_verify_false_warning() != 0) {
		return 1;
	}
	if (test_bad_cert_reg_failed() != 0) {
		return 1;
	}

	fprintf(stderr, "PASS: tls\n");
	return 0;
}
