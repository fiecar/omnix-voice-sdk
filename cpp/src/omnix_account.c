/**
 * Omnix Voice — account stub (SDK-010).
 * Full UA/account wiring lands in SDK-012. Password wipe contract is live now.
 */
#include "omnix_internal.h"

#include <re.h>
#include <baresip.h>

#include <string.h>

/* No persistent account handle in this stub stage. */

omnix_error_t omnix_account_setup(const omnix_config_t *config)
{
	char *pw_copy;

	if (!config) {
		return OMNIX_ERR_INVALID_CONFIG;
	}

	/*
	 * Password handling (Issue #1 §26):
	 * Copy caller-owned sip_password into Omnix-owned buffer, pass to
	 * account_set_auth_pass when a real account exists, then wipe ONLY
	 * the Omnix-owned copy. Never write into config->sip_password.
	 * Never put the password into the AOR (no ;auth_pass=).
	 */
	if (config->sip_password && config->sip_password[0] != '\0') {
		pw_copy = omnix_password_dup(config->sip_password);
		if (!pw_copy) {
			return OMNIX_ERR_INTERNAL;
		}

		/* Feed log filter so accidental logs cannot echo the secret. */
		omnix_log_filter_set_secret(pw_copy);

		/*
		 * SDK-010: no live struct account* yet (SDK-012). The wipe
		 * still runs exactly as it will after account_set_auth_pass().
		 * When SDK-012 lands, call account_set_auth_pass(acc, pw_copy)
		 * immediately before the wipe below.
		 */
		(void)0; /* placeholder for account_set_auth_pass(acc, pw_copy) */

		omnix_password_wipe_free(pw_copy);
		pw_copy = NULL;
	}

	return OMNIX_ERR_OK;
}

void omnix_account_teardown(void)
{
	omnix_log_filter_clear();
}
