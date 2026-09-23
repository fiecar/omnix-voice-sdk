/**
 * SDK-027: Codec configuration — G.711 baseline, codecs preference,
 * missing-Opus path (default still negotiates PCMU/PCMA).
 * Live negotiation with a SIP peer is gate H-3 / SDK-065 — not invented PASS.
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

static void fill_cfg(omnix_config_t *cfg, const char *codecs)
{
	memset(cfg, 0, sizeof(*cfg));
	cfg->sip_server = "sips:sip.example.com:5061";
	cfg->sip_user = "user@example.com";
	cfg->auth_user = "authuser";
	cfg->sip_password = "test-password-NOT-A-REAL-SECRET";
	cfg->display_name = "Omnix Codecs Test";
	cfg->verify_tls_cert = true;
	cfg->enable_srtp = true;
	cfg->codecs = codecs;
}

static int expect_pcmu_pcma_order(const char *first, const char *second)
{
	const char *c0 = omnix_test_account_codec_name(0);
	const char *c1 = omnix_test_account_codec_name(1);

	if (omnix_test_account_codec_count() != 2) {
		fprintf(stderr, "codec_count=%u\n",
			omnix_test_account_codec_count());
		return fail("expected exactly 2 account codecs (PCMU+PCMA)");
	}
	if (!c0 || !c1) {
		return fail("codec names NULL");
	}
	if (strcmp(c0, first) != 0 || strcmp(c1, second) != 0) {
		fprintf(stderr, "got %s,%s expected %s,%s\n", c0, c1, first,
			second);
		return fail("unexpected codec preference order");
	}
	return 0;
}

/* Default NULL codecs → "opus,pcmu,pcma"; Opus absent → WARNING + G.711. */
static int test_default_missing_opus(void)
{
	omnix_config_t cfg;

	fill_cfg(&cfg, NULL);

	if (omnix_init(&cfg) != OMNIX_ERR_OK) {
		return fail("omnix_init default codecs");
	}

	if (omnix_test_aucodec_g711_present() != 1) {
		omnix_shutdown();
		return fail("expected global PCMU+PCMA after g711 preload");
	}

	if (omnix_test_warned_codec_missing() != 1) {
		omnix_shutdown();
		return fail("expected WARNING for missing opus in default");
	}

	if (expect_pcmu_pcma_order("PCMU", "PCMA") != 0) {
		omnix_shutdown();
		return 1;
	}

	fprintf(stderr, "SDK-027: default → PCMU,PCMA (opus ignored) OK\n");
	omnix_shutdown();
	return 0;
}

static int test_explicit_default_string(void)
{
	omnix_config_t cfg;

	fill_cfg(&cfg, "opus,pcmu,pcma");

	if (omnix_init(&cfg) != OMNIX_ERR_OK) {
		return fail("omnix_init opus,pcmu,pcma");
	}

	if (omnix_test_warned_codec_missing() != 1) {
		omnix_shutdown();
		return fail("expected opus WARNING for explicit default");
	}

	if (expect_pcmu_pcma_order("PCMU", "PCMA") != 0) {
		omnix_shutdown();
		return 1;
	}

	omnix_shutdown();
	return 0;
}

static int test_g711_only_no_opus_warn(void)
{
	omnix_config_t cfg;

	fill_cfg(&cfg, "pcmu,pcma");

	if (omnix_init(&cfg) != OMNIX_ERR_OK) {
		return fail("omnix_init pcmu,pcma");
	}

	if (omnix_test_warned_codec_missing() != 0) {
		omnix_shutdown();
		return fail("unexpected missing-codec WARNING for G.711-only");
	}

	if (expect_pcmu_pcma_order("PCMU", "PCMA") != 0) {
		omnix_shutdown();
		return 1;
	}

	omnix_shutdown();
	return 0;
}

static int test_priority_pcma_first(void)
{
	omnix_config_t cfg;

	fill_cfg(&cfg, "pcma,pcmu");

	if (omnix_init(&cfg) != OMNIX_ERR_OK) {
		return fail("omnix_init pcma,pcmu");
	}

	if (expect_pcmu_pcma_order("PCMA", "PCMU") != 0) {
		omnix_shutdown();
		return 1;
	}

	omnix_shutdown();
	return 0;
}

/* Only Opus requested and Opus not compiled → INVALID_CONFIG. */
static int test_opus_only_invalid(void)
{
	omnix_config_t cfg;
	omnix_error_t err;

	fill_cfg(&cfg, "opus");
	err = omnix_init(&cfg);
	if (err != OMNIX_ERR_INVALID_CONFIG) {
		fprintf(stderr, "err=%d\n", (int)err);
		if (err == OMNIX_ERR_OK) {
			omnix_shutdown();
		}
		return fail("expected INVALID_CONFIG when only opus requested");
	}
	fprintf(stderr, "SDK-027: opus-only → INVALID_CONFIG OK\n");
	return 0;
}

int main(void)
{
	/*
	 * Static module list: CMake FATAL_ERROR if g711 absent / opus present
	 * in OMNIX_BARESIP_MODULES (configure-time evidence for SDK-027).
	 */
	if (test_default_missing_opus() != 0) {
		return 1;
	}
	if (test_explicit_default_string() != 0) {
		return 1;
	}
	if (test_g711_only_no_opus_warn() != 0) {
		return 1;
	}
	if (test_priority_pcma_first() != 0) {
		return 1;
	}
	if (test_opus_only_invalid() != 0) {
		return 1;
	}

	fprintf(stderr,
		"PASS: codecs (host; live SDP negotiate = H-3/SDK-065 SKIPPED)\n");
	return 0;
}
