/**
 * SDK-012: account model — TLS AOR, no password in AOR, dtls_srtp mediaenc.
 */
#include "omnix_voice/omnix_voice.h"
#include "omnix_internal.h"

#include <stdio.h>
#include <string.h>

static const char *k_password = "test-password-NOT-A-REAL-SECRET";

static int fail(const char *msg)
{
	fprintf(stderr, "FAIL: %s\n", msg);
	return 1;
}

static void fill_cfg(omnix_config_t *cfg)
{
	memset(cfg, 0, sizeof(*cfg));
	cfg->sip_server = "sips:sip.example.com:5061";
	cfg->sip_user = "user@example.com";
	cfg->auth_user = "authuser";
	cfg->sip_password = k_password;
	cfg->display_name = "Omnix Test";
	cfg->verify_tls_cert = true;
	cfg->enable_srtp = true;
}

static int assert_no_password(const char *label, const char *s)
{
	if (!s) {
		fprintf(stderr, "FAIL: %s is null\n", label);
		return 1;
	}
	if (strstr(s, "auth_pass") != NULL) {
		fprintf(stderr, "FAIL: %s contains auth_pass: %s\n", label, s);
		return 1;
	}
	if (strstr(s, k_password) != NULL) {
		fprintf(stderr, "FAIL: %s contains password\n", label);
		return 1;
	}
	return 0;
}

int main(void)
{
	omnix_config_t cfg;
	const char *aor;
	const char *aor_built;
	const char *mediaenc;
	const char *auth_user;
	const char *dname;

	fill_cfg(&cfg);

	if (omnix_init(&cfg) != OMNIX_ERR_OK) {
		return fail("omnix_init");
	}

	aor_built = omnix_test_account_aor_built();
	if (!aor_built || aor_built[0] == '\0') {
		omnix_shutdown();
		return fail("missing built AOR");
	}
	if (strstr(aor_built, "transport=tls") == NULL) {
		fprintf(stderr, "built AOR=%s\n", aor_built);
		omnix_shutdown();
		return fail("built AOR missing transport=tls");
	}
	if (assert_no_password("built AOR", aor_built)) {
		omnix_shutdown();
		return 1;
	}
	if (strstr(aor_built, "Omnix Test") == NULL) {
		fprintf(stderr, "built AOR=%s\n", aor_built);
		omnix_shutdown();
		return fail("built AOR missing display name");
	}

	if (!omnix_test_account_has_tls_transport()) {
		omnix_shutdown();
		return fail("account luri missing transport=tls");
	}

	aor = omnix_test_account_aor();
	if (!aor || aor[0] == '\0') {
		omnix_shutdown();
		return fail("missing account_aor");
	}
	if (assert_no_password("account_aor", aor)) {
		omnix_shutdown();
		return 1;
	}
	if (strstr(aor, "user@example.com") == NULL) {
		fprintf(stderr, "AOR=%s\n", aor);
		omnix_shutdown();
		return fail("account_aor missing user@domain");
	}

	dname = omnix_test_account_display_name();
	if (!dname || strcmp(dname, "Omnix Test") != 0) {
		fprintf(stderr, "display_name=%s\n", dname ? dname : "(null)");
		omnix_shutdown();
		return fail("expected display name Omnix Test");
	}

	mediaenc = omnix_test_account_mediaenc();
	if (!mediaenc || strcmp(mediaenc, "dtls_srtp") != 0) {
		fprintf(stderr, "mediaenc=%s\n",
			mediaenc ? mediaenc : "(null)");
		omnix_shutdown();
		return fail("expected mediaenc dtls_srtp");
	}

	auth_user = omnix_test_account_auth_user();
	if (!auth_user || strcmp(auth_user, "authuser") != 0) {
		fprintf(stderr, "auth_user=%s\n",
			auth_user ? auth_user : "(null)");
		omnix_shutdown();
		return fail("expected auth_user from config");
	}

	/* Caller-owned password buffer must be untouched. */
	if (strcmp(cfg.sip_password, k_password) != 0) {
		omnix_shutdown();
		return fail("caller sip_password was modified");
	}

	omnix_shutdown();

	/* Domain from sip_server host when sip_user has no '@'. */
	fill_cfg(&cfg);
	cfg.sip_user = "alice";
	cfg.auth_user = NULL;
	cfg.display_name = NULL;
	if (omnix_init(&cfg) != OMNIX_ERR_OK) {
		return fail("omnix_init user-only");
	}

	aor_built = omnix_test_account_aor_built();
	if (!aor_built ||
	    strstr(aor_built, "sip:alice@sip.example.com") == NULL) {
		fprintf(stderr, "built AOR=%s\n",
			aor_built ? aor_built : "(null)");
		omnix_shutdown();
		return fail("expected alice@sip.example.com from sip_server");
	}
	if (strstr(aor_built, "transport=tls") == NULL) {
		omnix_shutdown();
		return fail("user-only built AOR missing transport=tls");
	}
	if (!omnix_test_account_has_tls_transport()) {
		omnix_shutdown();
		return fail("user-only luri missing transport=tls");
	}
	auth_user = omnix_test_account_auth_user();
	if (!auth_user || strcmp(auth_user, "alice") != 0) {
		omnix_shutdown();
		return fail("auth_user should default to sip user part");
	}

	omnix_shutdown();

	fprintf(stderr, "PASS: account model\n");
	return 0;
}
