/**
 * SDK-052: Omnix error codes stay distinct, and a known password from
 * config must not show up in the log path, error-callback detail, the
 * account AOR, or omnix_call_info_t.
 */
#include "omnix_voice/omnix_voice.h"
#include "omnix_internal.h"

#include <stdio.h>
#include <stdint.h>
#include <string.h>

static const char *SECRET = "test-password-NOT-A-REAL-SECRET";

static char g_details[8][180];
static int g_detail_count;

static int fail(const char *msg)
{
	fprintf(stderr, "FAIL: %s\n", msg);
	return 1;
}

static int contains_secret(const char *text)
{
	return text && strstr(text, SECRET) != NULL;
}

static void on_error(omnix_error_t err, const char *detail, void *ctx)
{
	(void)err;
	(void)ctx;
	if (g_detail_count >= 8) {
		return;
	}
	g_details[g_detail_count][0] = '\0';
	if (detail) {
		snprintf(g_details[g_detail_count],
			 sizeof(g_details[g_detail_count]), "%s", detail);
	}
	++g_detail_count;
}

static int codes_are_dense(void)
{
	static const omnix_error_t codes[] = {
		OMNIX_ERR_OK,
		OMNIX_ERR_INITIALIZATION,
		OMNIX_ERR_INVALID_CONFIG,
		OMNIX_ERR_REGISTRATION_FAILED,
		OMNIX_ERR_AUTH_FAILED,
		OMNIX_ERR_NETWORK,
		OMNIX_ERR_TLS,
		OMNIX_ERR_MEDIA,
		OMNIX_ERR_CALL_FAILED,
		OMNIX_ERR_CALL_BUSY,
		OMNIX_ERR_CALL_REJECTED,
		OMNIX_ERR_TIMEOUT,
		OMNIX_ERR_NOT_REGISTERED,
		OMNIX_ERR_INVALID_STATE,
		OMNIX_ERR_PERMISSION_DENIED,
		OMNIX_ERR_TRANSFER_FAILED,
		OMNIX_ERR_NOT_SUPPORTED,
		OMNIX_ERR_INTERNAL,
	};
	size_t i;

	if (codes[0] != OMNIX_ERR_OK || codes[0] != 0) {
		return fail("OMNIX_ERR_OK must be 0");
	}
	for (i = 0; i < sizeof(codes) / sizeof(codes[0]); ++i) {
		if ((int)codes[i] != (int)i) {
			fprintf(stderr, "code[%zu]=%d\n", i, (int)codes[i]);
			return fail("error codes are not a dense 0..N map");
		}
	}
	return 0;
}

static int info_has_secret(const omnix_call_info_t *info)
{
	if (!info) {
		return 0;
	}
	return contains_secret(info->call_id) ||
	       contains_secret(info->peer_uri) ||
	       contains_secret(info->peer_display_name);
}

int main(void)
{
	omnix_config_t cfg;
	omnix_call_entry_t *entry;
	static int fake_call = 1;
	char call_id[128];
	const char *aor;
	const char *log;
	int i;

	if (codes_are_dense() != 0) {
		return 1;
	}

	memset(&cfg, 0, sizeof(cfg));
	cfg.sip_server = "sips:sip.example.com:5061";
	cfg.sip_user = "user@example.com";
	cfg.sip_password = SECRET;
	cfg.display_name = "Omnix";
	cfg.verify_tls_cert = true;
	cfg.enable_srtp = true;
	cfg.on_error = on_error;

	if (omnix_init(&cfg) != OMNIX_ERR_OK) {
		return fail("omnix_init");
	}

	aor = omnix_test_account_aor();
	if (!aor || aor[0] == '\0') {
		omnix_shutdown();
		return fail("missing account AOR");
	}
	if (contains_secret(aor) || contains_secret(omnix_test_account_aor_built())) {
		omnix_shutdown();
		return fail("password leaked into account AOR");
	}

	memset(call_id, 0, sizeof(call_id));
	if (omnix_call_make(SECRET, call_id, sizeof(call_id)) !=
	    OMNIX_ERR_NOT_REGISTERED) {
		omnix_shutdown();
		return fail("expected NOT_REGISTERED");
	}
	if (contains_secret(call_id)) {
		omnix_shutdown();
		return fail("password leaked into call id");
	}

	omnix_test_reset_last_log();
	{
		char msg[256];
		snprintf(msg, sizeof(msg), "auth pass=%s", SECRET);
		omnix_test_emit_via_log_path(msg);
	}
	log = omnix_test_last_log();
	if (!log || strstr(log, "[REDACTED]") == NULL || contains_secret(log)) {
		omnix_shutdown();
		return fail("password leaked into log output");
	}

	entry = omnix_test_install_call_slot(
		"call-1", (struct call *)(uintptr_t)&fake_call);
	if (!entry) {
		omnix_shutdown();
		return fail("install call slot");
	}
	if (info_has_secret(&entry->info)) {
		omnix_shutdown();
		return fail("password leaked into omnix_call_info_t");
	}

	for (i = 0; i < g_detail_count; ++i) {
		if (contains_secret(g_details[i])) {
			omnix_shutdown();
			return fail("password leaked into error detail");
		}
	}

	omnix_shutdown();
	fprintf(stderr, "PASS: error mapping\n");
	return 0;
}
