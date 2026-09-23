/**
 * SDK-021: Speaker preference — omnix_call_set_speaker stores enable in
 * omnix_state.speaker_enabled. Platform AudioManager / AVAudioSession
 * application is SDK-034 / SDK-042 (not host-testable here).
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

static void fill_cfg(omnix_config_t *cfg)
{
	memset(cfg, 0, sizeof(*cfg));
	cfg->sip_server = "sips:sip.example.com:5061";
	cfg->sip_user = "user@example.com";
	cfg->auth_user = "authuser";
	cfg->sip_password = "test-password-NOT-A-REAL-SECRET";
	cfg->display_name = "Omnix Speaker";
	cfg->verify_tls_cert = true;
	cfg->enable_srtp = true;
}

/** AC: before init -> INVALID_STATE; preference unread -> -1. */
static int test_uninit_rejected(void)
{
	omnix_error_t err;
	int pref;

	err = omnix_call_set_speaker(true);
	if (err != OMNIX_ERR_INVALID_STATE) {
		fprintf(stderr, "uninit set_speaker err=%d\n", (int)err);
		return fail("uninit expected INVALID_STATE");
	}

	pref = omnix_test_speaker_enabled();
	if (pref != -1) {
		fprintf(stderr, "uninit pref=%d\n", pref);
		return fail("uninit preference should be -1");
	}

	return 0;
}

/**
 * AC: C facade stores speaker preference (default false; set true/false).
 * Platform setSpeakerphoneOn / overrideOutputAudioPort deferred to SDK-034/042.
 */
static int test_store_preference(void)
{
	omnix_config_t cfg;
	omnix_error_t err;
	int pref;

	fill_cfg(&cfg);

	if (omnix_init(&cfg) != OMNIX_ERR_OK) {
		return fail("omnix_init");
	}

	pref = omnix_test_speaker_enabled();
	if (pref != 0) {
		omnix_shutdown();
		fprintf(stderr, "default pref=%d\n", pref);
		return fail("default speaker preference must be false");
	}

	err = omnix_call_set_speaker(true);
	if (err == OMNIX_ERR_NOT_SUPPORTED) {
		omnix_shutdown();
		return fail("set_speaker still stubbed NOT_SUPPORTED");
	}
	if (err != OMNIX_ERR_OK) {
		fprintf(stderr, "enable err=%d\n", (int)err);
		omnix_shutdown();
		return fail("enable expected OK");
	}

	pref = omnix_test_speaker_enabled();
	if (pref != 1) {
		omnix_shutdown();
		fprintf(stderr, "enabled pref=%d\n", pref);
		return fail("speaker preference must be true after enable");
	}

	err = omnix_call_set_speaker(false);
	if (err != OMNIX_ERR_OK) {
		fprintf(stderr, "disable err=%d\n", (int)err);
		omnix_shutdown();
		return fail("disable expected OK");
	}

	pref = omnix_test_speaker_enabled();
	if (pref != 0) {
		omnix_shutdown();
		fprintf(stderr, "disabled pref=%d\n", pref);
		return fail("speaker preference must be false after disable");
	}

	omnix_shutdown();

	pref = omnix_test_speaker_enabled();
	if (pref != -1) {
		fprintf(stderr, "post-shutdown pref=%d\n", pref);
		return fail("after shutdown preference should be -1");
	}

	return 0;
}

int main(void)
{
	int rc = 0;

	if (test_uninit_rejected() != 0) {
		rc = 1;
	}
	if (test_store_preference() != 0) {
		rc = 1;
	}

	if (rc == 0) {
		printf("PASS: speaker\n");
	}
	return rc;
}
