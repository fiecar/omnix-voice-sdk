/**
 * SDK-026: SRTP - dtls_srtp default mediaenc, static modules present,
 * enable_srtp=false WARNING while still forcing encryption.
 * Host has no live SIP/RTP peer; media-on-wire encryption is gate H-3 /
 * SDK-065 row 17 - not invented PASS here.
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

static void fill_cfg(omnix_config_t *cfg, bool enable_srtp)
{
	memset(cfg, 0, sizeof(*cfg));
	cfg->sip_server = "sips:sip.example.com:5061";
	cfg->sip_user = "user@example.com";
	cfg->auth_user = "authuser";
	cfg->sip_password = "test-password-NOT-A-REAL-SECRET";
	cfg->display_name = "Omnix SRTP Test";
	cfg->verify_tls_cert = true;
	cfg->enable_srtp = enable_srtp;
}

static int test_dtls_srtp_default(void)
{
	omnix_config_t cfg;
	const char *mediaenc;

	fill_cfg(&cfg, true);

	if (omnix_init(&cfg) != OMNIX_ERR_OK) {
		return fail("omnix_init enable_srtp=true");
	}

	mediaenc = omnix_test_account_mediaenc();
	if (!mediaenc || strcmp(mediaenc, "dtls_srtp") != 0) {
		fprintf(stderr, "mediaenc=%s\n",
			mediaenc ? mediaenc : "(null)");
		omnix_shutdown();
		return fail("expected account mediaenc dtls_srtp");
	}

	if (omnix_test_menc_dtls_srtp_present() != 1) {
		omnix_shutdown();
		return fail("expected menc_find(dtls_srtp) after init");
	}

	if (omnix_test_warned_srtp_off() != 0) {
		omnix_shutdown();
		return fail("unexpected enable_srtp=false WARNING");
	}

	fprintf(stderr, "SDK-026: mediaenc=%s menc=dtls_srtp OK\n", mediaenc);
	omnix_shutdown();
	return 0;
}

static int test_enable_srtp_false_still_forces(void)
{
	omnix_config_t cfg;
	const char *mediaenc;
	const char *log;

	fill_cfg(&cfg, false);

	if (omnix_init(&cfg) != OMNIX_ERR_OK) {
		return fail("omnix_init enable_srtp=false");
	}

	if (omnix_test_warned_srtp_off() != 1) {
		omnix_shutdown();
		return fail("expected enable_srtp=false WARNING");
	}

	log = omnix_test_last_log();
	/* last_log may be overwritten; sticky flag is authoritative. */
	if (log && strstr(log, "enable_srtp=false") != NULL) {
		fprintf(stderr, "last_log still has srtp warning: ok\n");
	}

	mediaenc = omnix_test_account_mediaenc();
	if (!mediaenc || strcmp(mediaenc, "dtls_srtp") != 0) {
		fprintf(stderr, "mediaenc=%s\n",
			mediaenc ? mediaenc : "(null)");
		omnix_shutdown();
		return fail("enable_srtp=false must still force dtls_srtp");
	}

	if (omnix_test_menc_dtls_srtp_present() != 1) {
		omnix_shutdown();
		return fail("menc dtls_srtp missing when enable_srtp=false");
	}

	omnix_shutdown();
	return 0;
}

int main(void)
{
	/*
	 * Static module list: CMake FATAL_ERROR if dtls_srtp/srtp absent from
	 * OMNIX_BARESIP_MODULES (configure-time evidence for SDK-026 AC #1).
	 */
	if (test_dtls_srtp_default() != 0) {
		return 1;
	}
	if (test_enable_srtp_false_still_forces() != 0) {
		return 1;
	}

	fprintf(stderr,
		"PASS: srtp (host; live media encrypt = H-3/SDK-065 SKIPPED)\n");
	return 0;
}
