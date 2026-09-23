/**
 * SDK-028: STUN support — stun_server unset → no STUN; set → medianat=stun
 * + stun URI on the account. TURN URIs → NOT_SUPPORTED.
 * Live NAT/STUN validation against a real SBC may be postponed
 * (KNOWN LIMITATIONS / gate H-3) — not invented PASS here.
 */
#include "omnix_voice/omnix_voice.h"
#include "omnix_internal.h"

#include <stdio.h>
#include <string.h>

static int fail(const char *msg)
{
	fprintf(stderr, "FAIL: %s\n", msg);
	return 1;
}

static void fill_cfg(omnix_config_t *cfg, const char *stun)
{
	memset(cfg, 0, sizeof(*cfg));
	cfg->sip_server = "sips:sip.example.com:5061";
	cfg->sip_user = "user@example.com";
	cfg->auth_user = "authuser";
	cfg->sip_password = "test-password-NOT-A-REAL-SECRET";
	cfg->display_name = "Omnix STUN Test";
	cfg->verify_tls_cert = true;
	cfg->enable_srtp = true;
	cfg->stun_server = stun;
}

static int test_stun_unset(void)
{
	omnix_config_t cfg;
	const char *mnat;
	const char *uri;

	fill_cfg(&cfg, NULL);

	if (omnix_init(&cfg) != OMNIX_ERR_OK) {
		return fail("omnix_init stun unset");
	}

	mnat = omnix_test_account_medianat();
	if (mnat != NULL && mnat[0] != '\0') {
		fprintf(stderr, "medianat=%s\n", mnat);
		omnix_shutdown();
		return fail("expected no medianat when stun_server unset");
	}

	uri = omnix_test_account_stun_uri();
	if (uri != NULL) {
		fprintf(stderr, "stun_uri=%s\n", uri);
		omnix_shutdown();
		return fail("expected no stun URI when stun_server unset");
	}

	/* Module may be linked but must not be required when unset. */
	fprintf(stderr, "SDK-028: stun unset → no medianat/uri OK\n");
	omnix_shutdown();
	return 0;
}

static int test_stun_set_uri(void)
{
	omnix_config_t cfg;
	const char *mnat;
	const char *uri;

	fill_cfg(&cfg, "stun:stun.example.com:3478");

	if (omnix_init(&cfg) != OMNIX_ERR_OK) {
		return fail("omnix_init stun URI");
	}

	mnat = omnix_test_account_medianat();
	if (!mnat || strcmp(mnat, "stun") != 0) {
		fprintf(stderr, "medianat=%s\n", mnat ? mnat : "(null)");
		omnix_shutdown();
		return fail("expected medianat=stun");
	}

	uri = omnix_test_account_stun_uri();
	if (!uri || strstr(uri, "stun.example.com") == NULL) {
		fprintf(stderr, "stun_uri=%s\n", uri ? uri : "(null)");
		omnix_shutdown();
		return fail("expected stun URI containing stun.example.com");
	}

	if (omnix_test_mnat_stun_present() != 1) {
		omnix_shutdown();
		return fail("expected mnat_find(stun) after configured init");
	}

	fprintf(stderr, "SDK-028: medianat=%s uri=%s OK\n", mnat, uri);
	omnix_shutdown();
	return 0;
}

static int test_stun_bare_host(void)
{
	omnix_config_t cfg;
	const char *mnat;
	const char *uri;

	fill_cfg(&cfg, "stun.example.com:3478");

	if (omnix_init(&cfg) != OMNIX_ERR_OK) {
		return fail("omnix_init bare host");
	}

	mnat = omnix_test_account_medianat();
	if (!mnat || strcmp(mnat, "stun") != 0) {
		omnix_shutdown();
		return fail("bare host: expected medianat=stun");
	}

	uri = omnix_test_account_stun_uri();
	if (!uri || strstr(uri, "stun.example.com") == NULL) {
		fprintf(stderr, "stun_uri=%s\n", uri ? uri : "(null)");
		omnix_shutdown();
		return fail("bare host: expected wrapped stun URI");
	}

	omnix_shutdown();
	return 0;
}

static int test_turn_rejected(void)
{
	omnix_config_t cfg;
	omnix_error_t err;

	fill_cfg(&cfg, "turn:turn.example.com:3478");

	err = omnix_init(&cfg);
	if (err != OMNIX_ERR_NOT_SUPPORTED) {
		fprintf(stderr, "err=%d\n", (int)err);
		if (err == OMNIX_ERR_OK) {
			omnix_shutdown();
		}
		return fail("expected OMNIX_ERR_NOT_SUPPORTED for turn:");
	}

	fprintf(stderr, "SDK-028: turn: → NOT_SUPPORTED OK\n");
	return 0;
}

int main(void)
{
	/*
	 * Static module list: CMake FATAL_ERROR if stun absent from
	 * OMNIX_BARESIP_MODULES (configure-time evidence for SDK-028).
	 */
	if (test_stun_unset() != 0) {
		return 1;
	}
	if (test_stun_set_uri() != 0) {
		return 1;
	}
	if (test_stun_bare_host() != 0) {
		return 1;
	}
	if (test_turn_rejected() != 0) {
		return 1;
	}

	fprintf(stderr,
		"PASS: stun (host; live NAT/STUN vs SBC = H-3 SKIPPED / "
		"KNOWN LIMITATIONS)\n");
	return 0;
}
