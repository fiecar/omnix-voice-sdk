/**
 * Omnix Voice SDK — C facade lifecycle (SDK-011).
 * Runs libre/baresip with re_main on a background thread.
 * Baresip types stay in this translation unit / internal headers only.
 */
#include "omnix_voice/omnix_voice.h"
#include "omnix_internal.h"

#include <re.h>
#include <baresip.h>

#include <openssl/crypto.h>

#include <stdio.h>
#include <string.h>

enum { OMNIX_ASYNC_WORKERS = 4 };

static struct omnix_state g_state;
static thrd_t g_re_tid;
static bool g_re_tid_valid;
static mtx_t g_ready_mtx;
static cnd_t g_ready_cnd;
static bool g_ready_sync_inited;
static bool g_re_ready;
static bool g_stack_up; /* libre/baresip initialized (for fail-path cleanup) */
static bool g_verify_tls_off_warned; /* SDK-025: sticky for host test */

struct omnix_state *omnix_state_get(void)
{
	return &g_state;
}

void omnix_lifecycle_on_re_ready(void)
{
	if (!g_ready_sync_inited) {
		return;
	}
	mtx_lock(&g_ready_mtx);
	g_re_ready = true;
	cnd_signal(&g_ready_cnd);
	mtx_unlock(&g_ready_mtx);
}

static int omnix_str_eq(const char *a, const char *b)
{
	if (!a && !b) {
		return 1;
	}
	if (!a || !b) {
		return 0;
	}
	return strcmp(a, b) == 0;
}

static char *omnix_strdup_or_null(const char *src)
{
	if (!src) {
		return NULL;
	}
	return omnix_password_dup(src); /* same allocator; non-secret use OK */
}

static void omnix_fingerprint_clear(void)
{
	omnix_password_wipe_free(g_state.fp_sip_server);
	omnix_password_wipe_free(g_state.fp_sip_user);
	omnix_password_wipe_free(g_state.fp_auth_user);
	omnix_password_wipe_free(g_state.fp_display_name);
	omnix_password_wipe_free(g_state.fp_stun_server);
	omnix_password_wipe_free(g_state.fp_audio_module);
	omnix_password_wipe_free(g_state.fp_codecs);
	g_state.fp_sip_server = NULL;
	g_state.fp_sip_user = NULL;
	g_state.fp_auth_user = NULL;
	g_state.fp_display_name = NULL;
	g_state.fp_stun_server = NULL;
	g_state.fp_audio_module = NULL;
	g_state.fp_codecs = NULL;
}

static omnix_error_t omnix_fingerprint_store(const omnix_config_t *config)
{
	omnix_fingerprint_clear();
	g_state.fp_sip_server = omnix_strdup_or_null(config->sip_server);
	g_state.fp_sip_user = omnix_strdup_or_null(config->sip_user);
	g_state.fp_auth_user = omnix_strdup_or_null(config->auth_user);
	g_state.fp_display_name = omnix_strdup_or_null(config->display_name);
	g_state.fp_stun_server = omnix_strdup_or_null(config->stun_server);
	g_state.fp_audio_module = omnix_strdup_or_null(config->audio_module);
	g_state.fp_codecs = omnix_strdup_or_null(config->codecs);
	/* OOM on required fields only — sip_server is expected for real use;
	 * allow NULL for lifecycle unit tests that pass placeholders. */
	return OMNIX_ERR_OK;
}

static bool omnix_config_same(const omnix_config_t *config)
{
	if (!config) {
		return false;
	}
	if (!omnix_str_eq(config->sip_server, g_state.fp_sip_server) ||
	    !omnix_str_eq(config->sip_user, g_state.fp_sip_user) ||
	    !omnix_str_eq(config->auth_user, g_state.fp_auth_user) ||
	    !omnix_str_eq(config->display_name, g_state.fp_display_name) ||
	    !omnix_str_eq(config->stun_server, g_state.fp_stun_server) ||
	    !omnix_str_eq(config->audio_module, g_state.fp_audio_module) ||
	    !omnix_str_eq(config->codecs, g_state.fp_codecs)) {
		return false;
	}
	if (config->verify_tls_cert != g_state.config.verify_tls_cert ||
	    config->enable_srtp != g_state.config.enable_srtp) {
		return false;
	}
	if (config->on_reg_state != g_state.config.on_reg_state ||
	    config->on_call_event != g_state.config.on_call_event ||
	    config->on_error != g_state.config.on_error ||
	    config->ctx != g_state.config.ctx) {
		return false;
	}
	/* sip_password intentionally excluded: Omnix-owned copy is wiped. */
	return true;
}

static void omnix_config_apply(omnix_config_t *dst, const omnix_config_t *src)
{
	*dst = *src;
	dst->sip_password = NULL; /* never retain caller password pointer */
}

static int omnix_re_thread_main(void *arg)
{
	(void)arg;
	(void)re_main(NULL);
	return 0;
}

static void omnix_ua_exit_handler(void *arg)
{
	(void)arg;
	re_cancel();
}

static void omnix_ready_sync_init(void)
{
	if (g_ready_sync_inited) {
		return;
	}
	mtx_init(&g_ready_mtx, mtx_plain);
	cnd_init(&g_ready_cnd);
	g_ready_sync_inited = true;
}

static void omnix_re_thread_stop_and_join(void)
{
	int err;

	if (!g_re_tid_valid) {
		return;
	}

	/*
	 * Stop via mqueue on the re thread (never re_thread_enter + re_cancel:
	 * that deadlocks because re_thread_leave skips unlock when polling is
	 * already false). Fallback: direct re_cancel + ready nudge.
	 */
	err = omnix_events_request_shutdown();
	if (err) {
		re_cancel();
		(void)omnix_events_request_ready_signal();
	}

	thrd_join(g_re_tid, NULL);
	g_re_tid_valid = false;
	g_state.re_thread_started = false;
}

static void omnix_stack_teardown_partial(void)
{
	omnix_call_registry_reset();
	omnix_account_teardown();
	omnix_re_thread_stop_and_join();
	omnix_events_shutdown();
	omnix_log_handler_unregister();
	omnix_account_unload_modules();

	if (g_stack_up) {
		ua_close();
		conf_close();
		baresip_close();
		re_thread_async_close();
		libre_close();
		g_stack_up = false;
	}

	omnix_fingerprint_clear();
	memset(&g_state, 0, sizeof(g_state));
	g_state.reg_state = OMNIX_REG_UNINITIALIZED;
	g_re_ready = false;
}

omnix_error_t omnix_init(const omnix_config_t *config)
{
	struct config *bcfg;
	omnix_error_t oerr;
	int err;
	int wait_i;
	static const char bare_conf[] = "sip_listen\t0.0.0.0:0\n";

	if (g_state.initialized) {
		if (omnix_config_same(config)) {
			return OMNIX_ERR_OK;
		}
		return OMNIX_ERR_INVALID_STATE;
	}
	if (!config) {
		return OMNIX_ERR_INVALID_CONFIG;
	}

	omnix_ready_sync_init();
	g_re_ready = false;
	g_verify_tls_off_warned = false;

	memset(&g_state, 0, sizeof(g_state));
	omnix_call_registry_reset();
	omnix_config_apply(&g_state.config, config);
	g_state.config.verify_tls_cert = config->verify_tls_cert;
	g_state.config.enable_srtp = config->enable_srtp;

	if (omnix_fingerprint_store(config) != OMNIX_ERR_OK) {
		omnix_stack_teardown_partial();
		return OMNIX_ERR_INTERNAL;
	}

	err = libre_init();
	if (err) {
		omnix_fingerprint_clear();
		memset(&g_state, 0, sizeof(g_state));
		return OMNIX_ERR_INITIALIZATION;
	}
	g_stack_up = true;

	err = re_thread_async_init(OMNIX_ASYNC_WORKERS);
	if (err) {
		omnix_stack_teardown_partial();
		return OMNIX_ERR_INITIALIZATION;
	}

	err = conf_configure_buf((const uint8_t *)bare_conf,
				 strlen(bare_conf));
	if (err) {
		omnix_stack_teardown_partial();
		return OMNIX_ERR_INITIALIZATION;
	}

	bcfg = conf_config();
	if (!bcfg) {
		omnix_stack_teardown_partial();
		return OMNIX_ERR_INITIALIZATION;
	}

	/* TLS transport only — no plain SIP (Issue #1 / SDK-025). */
	bcfg->sip.transports = (1u << SIP_TRANSP_TLS);
	bcfg->sip.transp = SIP_TRANSP_TLS;
	bcfg->sip.verify_server = config->verify_tls_cert;
	str_ncpy(bcfg->sip.local, "0.0.0.0:0", sizeof(bcfg->sip.local));

	err = baresip_init(bcfg);
	if (err) {
		omnix_stack_teardown_partial();
		return OMNIX_ERR_INITIALIZATION;
	}

	/* udp=false, tcp=false, tls=true — Issue #2 SDK-025. */
	err = ua_init("OmnixVoice/0.1.0", false, false, true);
	if (err) {
		omnix_stack_teardown_partial();
		return OMNIX_ERR_INITIALIZATION;
	}

	uag_set_exit_handler(omnix_ua_exit_handler, NULL);

	omnix_log_handler_register();
	omnix_test_reset_last_log();

	/*
	 * SDK-025: never disable cert validation silently. Log a prominent
	 * WARNING on every init when verify_tls_cert is false.
	 */
	if (!config->verify_tls_cert) {
		warning("OmnixVoice: WARNING verify_tls_cert=false — "
			"SIP TLS certificate validation is DISABLED. "
			"Do not use in production.\n");
		g_verify_tls_off_warned = true;
	}

	oerr = omnix_events_init();
	if (oerr != OMNIX_ERR_OK) {
		omnix_stack_teardown_partial();
		return oerr;
	}

	if (thrd_create(&g_re_tid, omnix_re_thread_main, NULL) !=
	    thrd_success) {
		omnix_stack_teardown_partial();
		return OMNIX_ERR_INITIALIZATION;
	}
	g_re_tid_valid = true;
	g_state.re_thread_started = true;

	/* Ask re_main to ack once the poll loop is live (via mqueue). */
	err = omnix_events_request_ready_signal();
	if (err) {
		omnix_stack_teardown_partial();
		return OMNIX_ERR_INITIALIZATION;
	}

	mtx_lock(&g_ready_mtx);
	for (wait_i = 0; wait_i < 5000 && !g_re_ready; ++wait_i) {
		mtx_unlock(&g_ready_mtx);
		sys_msleep(1);
		mtx_lock(&g_ready_mtx);
	}
	if (!g_re_ready) {
		mtx_unlock(&g_ready_mtx);
		omnix_stack_teardown_partial();
		return OMNIX_ERR_TIMEOUT;
	}
	mtx_unlock(&g_ready_mtx);

	/* Password wipe after stack + re_main are up (SDK-011 order). */
	oerr = omnix_account_setup(config);
	if (oerr != OMNIX_ERR_OK) {
		omnix_shutdown();
		return oerr;
	}

	g_state.reg_state = OMNIX_REG_UNREGISTERED;
	g_state.initialized = true;
	return OMNIX_ERR_OK;
}

void omnix_shutdown(void)
{
	if (!g_state.initialized && !g_stack_up) {
		return;
	}

	g_state.shutting_down = true;
	omnix_call_registry_reset();
	omnix_account_teardown();
	/* ua_stop_all(false) + re_cancel run on the re thread via mqueue. */
	omnix_re_thread_stop_and_join();
	omnix_events_shutdown();
	omnix_log_handler_unregister();
	omnix_account_unload_modules();

	if (g_stack_up) {
		ua_close();
		conf_close();
		baresip_close();
		re_thread_async_close();
		libre_close();
		g_stack_up = false;
	}

	omnix_fingerprint_clear();
	memset(&g_state, 0, sizeof(g_state));
	g_state.reg_state = OMNIX_REG_UNINITIALIZED;
	g_re_ready = false;
}

omnix_error_t omnix_register(void)
{
	int err;

	if (!g_state.initialized || !g_state.ua) {
		return OMNIX_ERR_INVALID_STATE;
	}

	/* App-visible REGISTERING before ua_register (state + mqueue cb). */
	(void)omnix_events_notify_registering();

	re_thread_enter();
	err = ua_register(g_state.ua);
	re_thread_leave();

	if (err) {
		(void)omnix_events_notify_reg_state(OMNIX_REG_FAILED, 0,
						    "register rejected");
		return OMNIX_ERR_REGISTRATION_FAILED;
	}

	return OMNIX_ERR_OK;
}

void omnix_unregister(void)
{
	if (!g_state.initialized || !g_state.ua) {
		return;
	}

	g_state.unregister_pending = true;

	re_thread_enter();
	ua_unregister(g_state.ua);
	re_thread_leave();
}

omnix_reg_state_t omnix_get_reg_state(void)
{
	if (!g_state.initialized) {
		return OMNIX_REG_UNINITIALIZED;
	}
	return g_state.reg_state;
}

/* --- SDK-025 test helpers (host / CI; not public API) --- */

int omnix_test_sip_verify_server(void)
{
	struct config *bcfg;

	if (!g_state.initialized) {
		return -1;
	}
	bcfg = conf_config();
	if (!bcfg) {
		return -1;
	}
	return bcfg->sip.verify_server ? 1 : 0;
}

int omnix_test_sip_tls_only(void)
{
	struct config *bcfg;
	uint32_t want = (1u << SIP_TRANSP_TLS);

	if (!g_state.initialized) {
		return -1;
	}
	bcfg = conf_config();
	if (!bcfg) {
		return -1;
	}
	if (bcfg->sip.transports != want) {
		return 0;
	}
	if (bcfg->sip.transp != SIP_TRANSP_TLS) {
		return 0;
	}
	return 1;
}

const char *omnix_test_openssl_version(void)
{
	/*
	 * Runtime string from the linked OpenSSL (host may use system 3.x;
	 * Android/iOS artifacts MUST use SDK-066 pinned 3.5.x via
	 * OMNIX_OPENSSL_ROOT — never system OpenSSL).
	 */
	return OpenSSL_version(OPENSSL_VERSION);
}

int omnix_test_warned_verify_tls_off(void)
{
	return g_verify_tls_off_warned ? 1 : 0;
}
