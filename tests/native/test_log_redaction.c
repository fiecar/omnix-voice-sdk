/**
 * Unit test: password strings through the Omnix log path become [REDACTED].
 * Build: enabled when OMNIX_BUILD_TESTS=ON (host or Android executable).
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

int main(void)
{
	const char *secret = "test-password-NOT-A-REAL-SECRET";
	char msg[256];
	omnix_config_t cfg;

	memset(&cfg, 0, sizeof(cfg));
	cfg.sip_server = "sips:sip.example.com:5061";
	cfg.sip_user = "user@example.com";
	cfg.sip_password = secret;
	cfg.verify_tls_cert = true;
	cfg.enable_srtp = true;

	if (omnix_init(&cfg) != OMNIX_ERR_OK) {
		return fail("omnix_init");
	}

	omnix_test_reset_last_log();
	snprintf(msg, sizeof(msg), "auth digest pass=%s realm=example", secret);
	omnix_test_emit_via_log_path(msg);

	{
		const char *last = omnix_test_last_log();
		if (!last || last[0] == '\0') {
			omnix_shutdown();
			return fail("no log captured");
		}
		if (strstr(last, secret) != NULL) {
			omnix_shutdown();
			return fail("secret leaked into log output");
		}
		if (strstr(last, "[REDACTED]") == NULL) {
			omnix_shutdown();
			return fail("expected [REDACTED] in log output");
		}
	}

	omnix_shutdown();
	fprintf(stderr, "PASS: log redaction\n");
	return 0;
}
