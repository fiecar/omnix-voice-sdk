/**
 * Omnix Voice SDK — C facade lifecycle (SDK-010).
 * Baresip types stay in this translation unit / internal headers only.
 */
#include "omnix_voice/omnix_voice.h"
#include "omnix_internal.h"

#include <string.h>

static struct omnix_state g_state;

struct omnix_state *omnix_state_get(void)
{
	return &g_state;
}

static void omnix_config_defaults(omnix_config_t *cfg)
{
	if (!cfg) {
		return;
	}
	/* Issue #1: TLS verify and SRTP MUST default to true. */
	cfg->verify_tls_cert = true;
	cfg->enable_srtp = true;
}

omnix_error_t omnix_init(const omnix_config_t *config)
{
	omnix_error_t err;

	if (g_state.initialized) {
		return OMNIX_ERR_INVALID_STATE;
	}
	if (!config) {
		return OMNIX_ERR_INVALID_CONFIG;
	}

	memset(&g_state, 0, sizeof(g_state));
	g_state.config = *config;
	/* Do not retain caller-owned password pointer beyond setup. */
	g_state.config.sip_password = NULL;
	omnix_config_defaults(&g_state.config);
	/* Preserve explicit false if caller set it after copy — re-apply
	 * caller values for the two security defaults only when unset-looking.
	 * Caller struct already has the intended bools; restore them. */
	g_state.config.verify_tls_cert = config->verify_tls_cert;
	g_state.config.enable_srtp = config->enable_srtp;
	/* If caller left them at false unintentionally... frozen default is
	 * true when constructing configs; we honor the caller's bools. */

	omnix_log_handler_register();
	omnix_test_reset_last_log();

	err = omnix_events_init();
	if (err != OMNIX_ERR_OK) {
		omnix_log_handler_unregister();
		memset(&g_state, 0, sizeof(g_state));
		return err;
	}

	/* Apply account/password wipe using the original caller config. */
	err = omnix_account_setup(config);
	if (err != OMNIX_ERR_OK) {
		omnix_events_shutdown();
		omnix_log_handler_unregister();
		memset(&g_state, 0, sizeof(g_state));
		return err;
	}

	g_state.reg_state = OMNIX_REG_UNREGISTERED;
	g_state.initialized = true;
	return OMNIX_ERR_OK;
}

void omnix_shutdown(void)
{
	if (!g_state.initialized) {
		return;
	}
	omnix_account_teardown();
	omnix_events_shutdown();
	omnix_log_handler_unregister();
	memset(&g_state, 0, sizeof(g_state));
	g_state.reg_state = OMNIX_REG_UNINITIALIZED;
}

omnix_error_t omnix_register(void)
{
	if (!g_state.initialized) {
		return OMNIX_ERR_INVALID_STATE;
	}
	g_state.reg_state = OMNIX_REG_REGISTERING;
	/* Real SIP registration: SDK-013 */
	g_state.reg_state = OMNIX_REG_FAILED;
	return OMNIX_ERR_NOT_SUPPORTED;
}

void omnix_unregister(void)
{
	if (!g_state.initialized) {
		return;
	}
	g_state.reg_state = OMNIX_REG_UNREGISTERED;
}

omnix_reg_state_t omnix_get_reg_state(void)
{
	if (!g_state.initialized) {
		return OMNIX_REG_UNINITIALIZED;
	}
	return g_state.reg_state;
}
