/**
 * SDK-011: lifecycle — init, double-init idempotency, clean shutdown, no leaks.
 */
#include "omnix_voice/omnix_voice.h"

#include <re.h>
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
	cfg->sip_password = "test-password-NOT-A-REAL-SECRET";
	cfg->verify_tls_cert = true;
	cfg->enable_srtp = true;
}

int main(void)
{
	omnix_config_t cfg;
	omnix_config_t cfg2;
	struct memstat mstat;
	int err;

	fill_cfg(&cfg);

	if (omnix_init(&cfg) != OMNIX_ERR_OK) {
		return fail("omnix_init");
	}

	/* Idempotent: same config -> OK */
	if (omnix_init(&cfg) != OMNIX_ERR_OK) {
		omnix_shutdown();
		return fail("double omnix_init same config");
	}

	/* Different config while live -> INVALID_STATE */
	fill_cfg(&cfg2);
	cfg2.sip_user = "other@example.com";
	if (omnix_init(&cfg2) != OMNIX_ERR_INVALID_STATE) {
		omnix_shutdown();
		return fail("expected INVALID_STATE for different config");
	}

	if (omnix_get_reg_state() != OMNIX_REG_UNREGISTERED) {
		omnix_shutdown();
		return fail("expected UNREGISTERED after init");
	}

	omnix_shutdown();

	if (omnix_get_reg_state() != OMNIX_REG_UNINITIALIZED) {
		return fail("expected UNINITIALIZED after shutdown");
	}

	/* Second full cycle (proves clean re-init after shutdown). */
	fill_cfg(&cfg);
	if (omnix_init(&cfg) != OMNIX_ERR_OK) {
		return fail("omnix_init after shutdown");
	}
	omnix_shutdown();

	mem_debug();
	err = mem_get_stat(&mstat);
	if (err == 0) {
		if (mstat.bytes_cur != 0 || mstat.blocks_cur != 0) {
			fprintf(stderr,
				"FAIL: leak bytes=%u blocks=%u\n",
				(unsigned)mstat.bytes_cur,
				(unsigned)mstat.blocks_cur);
			return 1;
		}
	}
	else {
		fprintf(stderr,
			"NOTE: mem_get_stat unavailable (%d); mem_debug printed\n",
			err);
	}

	fprintf(stderr, "PASS: lifecycle\n");
	return 0;
}
