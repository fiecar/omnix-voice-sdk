/**
 * SDK-015: Call model — internal registry (8 slots), find helpers,
 * omnix_call_info_t populated from Baresip call accessors.
 */
#include "omnix_voice/omnix_voice.h"
#include "omnix_internal.h"

#include <re.h>
#include <baresip.h>

#include <stdint.h>
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
	cfg->display_name = "Omnix Call Model";
	cfg->verify_tls_cert = true;
	cfg->enable_srtp = true;
}

/** AC: Registry supports 8 calls; find_by_id / find_by_ptr work. */
static int test_registry_capacity_and_find(void)
{
	omnix_call_entry_t *entries[8];
	omnix_call_entry_t *extra;
	omnix_call_entry_t *found;
	char idbuf[32];
	int i;
	/* Distinct fake pointers — never dereferenced by registry helpers. */
	struct call *fakes[8];

	omnix_call_registry_reset();

	if (omnix_call_registry_capacity() != 8) {
		return fail("capacity != 8");
	}
	if (omnix_call_registry_count() != 0) {
		return fail("count != 0 after reset");
	}

	for (i = 0; i < 8; ++i) {
		fakes[i] = (struct call *)(uintptr_t)(0x1000 + (unsigned)i * 16);
		snprintf(idbuf, sizeof(idbuf), "call-id-%d", i);
		entries[i] = omnix_test_install_call_slot(idbuf, fakes[i]);
		if (!entries[i]) {
			fprintf(stderr, "install slot %d failed\n", i);
			return fail("install slot");
		}
	}

	if (omnix_call_registry_count() != 8) {
		return fail("count != 8 when full");
	}

	extra = omnix_test_install_call_slot("call-id-overflow",
					     (struct call *)(uintptr_t)0xDEAD);
	if (extra != NULL) {
		return fail("9th slot should fail");
	}

	found = omnix_find_call_by_id("call-id-3");
	if (!found || found != entries[3]) {
		return fail("find_call_by_id");
	}
	if (strcmp(found->call_id, "call-id-3") != 0) {
		return fail("find_call_by_id call_id mismatch");
	}

	found = omnix_find_call_by_ptr(fakes[5]);
	if (!found || found != entries[5]) {
		return fail("find_call_by_ptr");
	}

	if (omnix_find_call_by_id("missing") != NULL) {
		return fail("find missing id");
	}
	if (omnix_find_call_by_ptr((struct call *)(uintptr_t)0xBEEF) != NULL) {
		return fail("find missing ptr");
	}

	omnix_free_call_slot(entries[2]);
	if (omnix_find_call_by_id("call-id-2") != NULL) {
		return fail("freed slot still findable by id");
	}
	if (omnix_call_registry_count() != 7) {
		return fail("count after free");
	}

	/* Reuse freed slot */
	entries[2] = omnix_test_install_call_slot("call-id-2-reused", fakes[2]);
	if (!entries[2]) {
		return fail("reuse freed slot");
	}
	if (omnix_call_registry_count() != 8) {
		return fail("count after reuse");
	}

	omnix_call_registry_reset();
	if (omnix_call_registry_count() != 0) {
		return fail("count after final reset");
	}

	return 0;
}

/**
 * AC: omnix_call_info_t populated from Baresip call struct via
 * call_id / call_peeruri / call_peername / call_is_outgoing / call_is_onhold.
 */
static int test_info_from_baresip_call(void)
{
	omnix_config_t cfg;
	struct call *call = NULL;
	omnix_call_entry_t *entry;
	omnix_call_entry_t *by_id;
	omnix_call_entry_t *by_ptr;
	const char *peer = "sip:peer@example.com";
	int err;

	fill_cfg(&cfg);
	if (omnix_init(&cfg) != OMNIX_ERR_OK) {
		return fail("omnix_init");
	}

	err = omnix_test_make_baresip_outgoing_call(&call, peer);
	if (err != 0 || !call) {
		fprintf(stderr, "make call err=%d\n", err);
		omnix_shutdown();
		return fail("make baresip outgoing call");
	}

	re_thread_enter();
	entry = omnix_alloc_call_slot(call);
	re_thread_leave();
	if (!entry) {
		omnix_test_release_baresip_call(call);
		omnix_shutdown();
		return fail("alloc_call_slot");
	}

	if (entry->baresip_call != call) {
		omnix_free_call_slot(entry);
		omnix_test_release_baresip_call(call);
		omnix_shutdown();
		return fail("baresip_call pointer");
	}
	if (entry->call_id[0] == '\0' ||
	    strcmp(entry->call_id, call_id(call)) != 0) {
		omnix_free_call_slot(entry);
		omnix_test_release_baresip_call(call);
		omnix_shutdown();
		return fail("entry call_id from call_id()");
	}
	if (strcmp(entry->info.call_id, entry->call_id) != 0) {
		omnix_free_call_slot(entry);
		omnix_test_release_baresip_call(call);
		omnix_shutdown();
		return fail("info.call_id");
	}
	if (!entry->info.is_outgoing) {
		omnix_free_call_slot(entry);
		omnix_test_release_baresip_call(call);
		omnix_shutdown();
		return fail("info.is_outgoing from call_is_outgoing()");
	}
	if (entry->info.is_on_hold != call_is_onhold(call)) {
		omnix_free_call_slot(entry);
		omnix_test_release_baresip_call(call);
		omnix_shutdown();
		return fail("info.is_on_hold from call_is_onhold()");
	}
	if (!entry->info.peer_uri[0] ||
	    strstr(entry->info.peer_uri, "peer@example.com") == NULL) {
		fprintf(stderr, "peer_uri='%s'\n", entry->info.peer_uri);
		omnix_free_call_slot(entry);
		omnix_test_release_baresip_call(call);
		omnix_shutdown();
		return fail("info.peer_uri from call_peeruri()");
	}
	if (entry->info.state != OMNIX_CALL_OUTGOING &&
	    entry->info.state != OMNIX_CALL_RINGING &&
	    entry->info.state != OMNIX_CALL_EARLY_MEDIA &&
	    entry->info.state != OMNIX_CALL_CONNECTED &&
	    entry->info.state != OMNIX_CALL_FAILED &&
	    entry->info.state != OMNIX_CALL_ENDED) {
		/*
		 * After call_connect, state is OUTGOING unless invite path
		 * advanced further; accept common post-connect states.
		 */
		fprintf(stderr, "unexpected state=%d\n", (int)entry->info.state);
		omnix_free_call_slot(entry);
		omnix_test_release_baresip_call(call);
		omnix_shutdown();
		return fail("info.state mapping");
	}

	by_id = omnix_find_call_by_id(entry->call_id);
	by_ptr = omnix_find_call_by_ptr(call);
	if (by_id != entry || by_ptr != entry) {
		omnix_free_call_slot(entry);
		omnix_test_release_baresip_call(call);
		omnix_shutdown();
		return fail("find after real alloc");
	}

	if (omnix_call_get_state(entry->call_id) != entry->info.state) {
		omnix_free_call_slot(entry);
		omnix_test_release_baresip_call(call);
		omnix_shutdown();
		return fail("omnix_call_get_state");
	}

	omnix_free_call_slot(entry);
	omnix_test_release_baresip_call(call);
	omnix_shutdown();
	return 0;
}

int main(void)
{
	if (test_registry_capacity_and_find() != 0) {
		return 1;
	}
	if (test_info_from_baresip_call() != 0) {
		return 1;
	}

	fprintf(stderr, "PASS: call_model\n");
	return 0;
}
