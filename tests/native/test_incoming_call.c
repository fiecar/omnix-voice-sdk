/**
 * SDK-017: Incoming call — BEVENT_CALL_INCOMING → on_call_event(INCOMING)
 * via mqueue; registry tracking; busy hangup when full.
 *
 * Scope: foreground / process-alive only (no PushKit/FCM/killed-app).
 */
#include "omnix_voice/omnix_voice.h"
#include "omnix_internal.h"

#include <re.h>

#include <stdint.h>
#include <stdio.h>
#include <string.h>

enum { MAX_CB = 16 };

struct call_cb_rec {
	omnix_call_state_t state;
	omnix_call_info_t info;
};

static struct call_cb_rec g_cbs[MAX_CB];
static int g_cb_count;
static void *g_cb_ctx_seen;

static int fail(const char *msg)
{
	fprintf(stderr, "FAIL: %s\n", msg);
	return 1;
}

static void on_call(omnix_call_state_t state, const omnix_call_info_t *call,
		    void *ctx)
{
	if (g_cb_count >= MAX_CB || !call) {
		return;
	}
	g_cbs[g_cb_count].state = state;
	g_cbs[g_cb_count].info = *call;
	g_cb_ctx_seen = ctx;
	++g_cb_count;
}

static void reset_cbs(void)
{
	memset(g_cbs, 0, sizeof(g_cbs));
	g_cb_count = 0;
	g_cb_ctx_seen = NULL;
}

static void fill_cfg(omnix_config_t *cfg, void *ctx)
{
	memset(cfg, 0, sizeof(*cfg));
	cfg->sip_server = "sips:sip.example.com:5061";
	cfg->sip_user = "user@example.com";
	cfg->auth_user = "authuser";
	cfg->sip_password = "test-password-NOT-A-REAL-SECRET";
	cfg->display_name = "Omnix Incoming Call";
	cfg->verify_tls_cert = true;
	cfg->enable_srtp = true;
	cfg->on_call_event = on_call;
	cfg->ctx = ctx;
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

/**
 * AC: Incoming via UA/bevent; on_call_event(OMNIX_CALL_INCOMING) outside
 * re lock (mqueue); call tracked in registry.
 */
static int test_incoming_event_and_registry(void)
{
	omnix_config_t cfg;
	static int ctx_token = 0x1701;
	omnix_call_entry_t *entry;
	const char *peer = "sip:peer@127.0.0.1";

	reset_cbs();
	fill_cfg(&cfg, &ctx_token);

	if (omnix_init(&cfg) != OMNIX_ERR_OK) {
		return fail("omnix_init");
	}

	if (omnix_test_inject_incoming_bevent(peer) != 0) {
		omnix_shutdown();
		return fail("inject BEVENT_CALL_INCOMING");
	}

	if (wait_cb_at_least(1, 3000) != 0) {
		omnix_shutdown();
		return fail("timeout waiting for on_call_event");
	}

	if (g_cbs[0].state != OMNIX_CALL_INCOMING) {
		fprintf(stderr, "state=%d\n", (int)g_cbs[0].state);
		omnix_shutdown();
		return fail("expected OMNIX_CALL_INCOMING");
	}
	if (g_cb_ctx_seen != &ctx_token) {
		omnix_shutdown();
		return fail("callback ctx mismatch");
	}
	if (g_cbs[0].info.call_id[0] == '\0') {
		omnix_shutdown();
		return fail("empty call_id in callback");
	}
	if (g_cbs[0].info.is_outgoing) {
		omnix_shutdown();
		return fail("expected is_outgoing=false");
	}
	if (g_cbs[0].info.state != OMNIX_CALL_INCOMING) {
		omnix_shutdown();
		return fail("info.state != INCOMING");
	}

	entry = omnix_find_call_by_id(g_cbs[0].info.call_id);
	if (!entry) {
		omnix_shutdown();
		return fail("call not in registry");
	}
	if (omnix_call_get_state(g_cbs[0].info.call_id) != OMNIX_CALL_INCOMING) {
		omnix_shutdown();
		return fail("get_state != INCOMING");
	}
	if (entry->info.is_outgoing) {
		omnix_shutdown();
		return fail("registry is_outgoing should be false");
	}

	omnix_shutdown();
	return 0;
}

/**
 * AC: registry full → call_hangup(486 Busy Here); no INCOMING callback.
 */
static int test_incoming_busy_when_full(void)
{
	omnix_config_t cfg;
	static int ctx_token = 0x1702;
	omnix_call_entry_t *slots[8];
	char idbuf[32];
	int i;
	unsigned before;

	reset_cbs();
	fill_cfg(&cfg, &ctx_token);

	if (omnix_init(&cfg) != OMNIX_ERR_OK) {
		return fail("omnix_init");
	}

	for (i = 0; i < 8; ++i) {
		snprintf(idbuf, sizeof(idbuf), "busy-slot-%d", i);
		slots[i] = omnix_test_install_call_slot(
			idbuf, (struct call *)(uintptr_t)(0x2000 + (unsigned)i * 16));
		if (!slots[i]) {
			omnix_shutdown();
			return fail("fill registry");
		}
	}
	if (omnix_call_registry_count() != 8) {
		omnix_shutdown();
		return fail("registry not full");
	}

	before = omnix_call_registry_count();
	if (omnix_test_inject_incoming_bevent("sip:busy@127.0.0.1") != 0) {
		omnix_shutdown();
		return fail("inject when full");
	}

	/* Hangup is sync under re lock; allow mqueue drain — expect no cb. */
	(void)wait_cb_at_least(1, 200);
	if (g_cb_count != 0) {
		omnix_shutdown();
		return fail("should not fire INCOMING when busy");
	}
	if (omnix_call_registry_count() != before) {
		omnix_shutdown();
		return fail("registry count changed on busy");
	}

	omnix_shutdown();
	return 0;
}

int main(void)
{
	int rc = 0;

	if (test_incoming_event_and_registry() != 0) {
		rc = 1;
	}
	if (test_incoming_busy_when_full() != 0) {
		rc = 1;
	}

	if (rc == 0) {
		printf("PASS: incoming_call\n");
	}
	return rc;
}
