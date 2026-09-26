/**
 * SDK-052: facade state guards without a SIP server.
 * init / same-config re-init / shutdown, make before register,
 * answer of an unknown id, DTMF digit rejection, hold before CONNECTED.
 */
#include "omnix_voice/omnix_voice.h"

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
	char call_id[128];
	omnix_error_t err;

	fill_cfg(&cfg);
	if (omnix_init(&cfg) != OMNIX_ERR_OK) {
		return fail("omnix_init");
	}
	if (omnix_init(&cfg) != OMNIX_ERR_OK) {
		omnix_shutdown();
		return fail("double-init same config");
	}
	if (omnix_get_reg_state() != OMNIX_REG_UNREGISTERED) {
		omnix_shutdown();
		return fail("expected UNREGISTERED after init");
	}

	memset(call_id, 0x5a, sizeof(call_id));
	err = omnix_call_make("sip:peer@example.com", call_id, sizeof(call_id));
	if (err != OMNIX_ERR_NOT_REGISTERED) {
		fprintf(stderr, "make err=%d\n", (int)err);
		omnix_shutdown();
		return fail("makeCall before register");
	}

	err = omnix_call_answer("no-such-call-id");
	if (err != OMNIX_ERR_INVALID_STATE) {
		fprintf(stderr, "answer err=%d\n", (int)err);
		omnix_shutdown();
		return fail("answer invalid id");
	}

	/* Digit check runs before the call lookup when call_id is non-empty. */
	err = omnix_call_send_dtmf("no-such-call-id", '!');
	if (err != OMNIX_ERR_INVALID_CONFIG) {
		fprintf(stderr, "dtmf err=%d\n", (int)err);
		omnix_shutdown();
		return fail("invalid DTMF digit");
	}
	err = omnix_call_send_dtmf("no-such-call-id", '5');
	if (err != OMNIX_ERR_INVALID_STATE) {
		omnix_shutdown();
		return fail("valid digit still needs a call");
	}

	err = omnix_call_hold("no-such-call-id");
	if (err != OMNIX_ERR_INVALID_STATE) {
		fprintf(stderr, "hold err=%d\n", (int)err);
		omnix_shutdown();
		return fail("hold before connected");
	}

	omnix_shutdown();
	if (omnix_get_reg_state() != OMNIX_REG_UNINITIALIZED) {
		return fail("expected UNINITIALIZED after shutdown");
	}
	if (omnix_call_hold("no-such-call-id") != OMNIX_ERR_INVALID_STATE) {
		return fail("hold after shutdown");
	}

	fprintf(stderr, "PASS: state machine\n");
	return 0;
}
