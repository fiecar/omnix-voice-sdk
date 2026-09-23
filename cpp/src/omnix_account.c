/**
 * Omnix Voice — SIP account / UA from omnix_config_t (SDK-012).
 * AOR never contains the password; auth via account_set_auth_pass only.
 * SDK-027: G.711 baseline + codecs preference from omnix_config_t.codecs.
 */
#include "omnix_internal.h"

#include <re.h>
#include <baresip.h>

#include <errno.h>
#include <string.h>

enum {
	OMNIX_AOR_MAX = 512,
	OMNIX_HOST_MAX = 256,
	OMNIX_USER_MAX = 128,
	OMNIX_CODECS_CFG_MAX = 256,
	OMNIX_CODEC_TOKEN_MAX = 64,
};

/* Issue #1 / SDK-027: public default preference (Opus ignored until SDK-067). */
#define OMNIX_CODECS_DEFAULT "opus,pcmu,pcma"

static bool g_codec_missing_warned; /* sticky for host tests */

/**
 * Filter omnix_config_t.codecs to codecs actually registered in
 * baresip_aucodecl(). Missing entries (e.g. opus before SDK-067) log a
 * WARNING and are skipped. If nothing remains → INVALID_CONFIG.
 */
static omnix_error_t omnix_account_apply_codecs(struct account *acc,
						const char *codecs_cfg)
{
	char input[OMNIX_CODECS_CFG_MAX];
	char filtered[OMNIX_CODECS_CFG_MAX];
	char token[OMNIX_CODEC_TOKEN_MAX];
	const char *src;
	const char *p;
	size_t filtered_len = 0;
	unsigned kept = 0;
	int err;

	if (!acc) {
		return OMNIX_ERR_INTERNAL;
	}

	src = (codecs_cfg && codecs_cfg[0] != '\0') ? codecs_cfg
						    : OMNIX_CODECS_DEFAULT;
	if (strlen(src) >= sizeof(input)) {
		return OMNIX_ERR_INVALID_CONFIG;
	}
	str_ncpy(input, src, sizeof(input));

	filtered[0] = '\0';
	p = input;
	while (*p) {
		char name[OMNIX_CODEC_TOKEN_MAX];
		struct pl pl_cname, pl_srate, pl_ch = PL_INIT;
		uint32_t srate = 8000;
		uint8_t ch = 1;
		size_t ti = 0;
		const struct aucodec *ac;

		while (*p == ' ' || *p == '\t' || *p == ',') {
			++p;
		}
		if (*p == '\0') {
			break;
		}

		while (*p && *p != ',' && *p != ' ' && *p != '\t' &&
		       ti + 1 < sizeof(token)) {
			token[ti++] = *p++;
		}
		token[ti] = '\0';
		while (*p == ' ' || *p == '\t') {
			++p;
		}
		if (*p == ',') {
			++p;
		}
		if (token[0] == '\0') {
			continue;
		}

		str_ncpy(name, token, sizeof(name));
		/* Format: "codec" or "codec/srate/ch" (baresip account.c). */
		if (0 == re_regex(token, str_len(token),
				  "[^/]+/[0-9]+[/]*[0-9]*", &pl_cname,
				  &pl_srate, NULL, &pl_ch)) {
			(void)pl_strcpy(&pl_cname, name, sizeof(name));
			srate = pl_u32(&pl_srate);
			if (pl_isset(&pl_ch)) {
				ch = (uint8_t)pl_u32(&pl_ch);
			}
		}

		ac = aucodec_find(baresip_aucodecl(), name, srate, ch);
		if (!ac) {
			warning("OmnixVoice: WARNING codec '%s' not compiled "
				"in — ignored\n",
				token);
			g_codec_missing_warned = true;
			continue;
		}

		if (kept > 0) {
			if (filtered_len + 1 >= sizeof(filtered)) {
				return OMNIX_ERR_INVALID_CONFIG;
			}
			filtered[filtered_len++] = ',';
			filtered[filtered_len] = '\0';
		}
		if (filtered_len + strlen(token) >= sizeof(filtered)) {
			return OMNIX_ERR_INVALID_CONFIG;
		}
		memcpy(filtered + filtered_len, token, strlen(token) + 1);
		filtered_len += strlen(token);
		++kept;
	}

	if (kept == 0) {
		warning("OmnixVoice: no usable codecs after filtering "
			"(config='%s')\n",
			src);
		return OMNIX_ERR_INVALID_CONFIG;
	}

	err = account_set_audio_codecs(acc, filtered);
	if (err) {
		return OMNIX_ERR_INITIALIZATION;
	}
	return OMNIX_ERR_OK;
}

/**
 * Extract host from sip_server (e.g. "sips:sip.example.com:5061" →
 * "sip.example.com"). Brackets kept for IPv6 literals.
 */
static int omnix_sip_host_from_server(const char *sip_server,
				      char *host, size_t host_sz)
{
	const char *p;
	const char *end;
	size_t len;

	if (!sip_server || !sip_server[0] || !host || host_sz == 0) {
		return EINVAL;
	}

	p = sip_server;
	if (0 == strncmp(p, "sips:", 5)) {
		p += 5;
	}
	else if (0 == strncmp(p, "sip:", 4)) {
		p += 4;
	}
	if (0 == strncmp(p, "//", 2)) {
		p += 2;
	}

	if (p[0] == '[') {
		end = strchr(p, ']');
		if (!end) {
			return EINVAL;
		}
		len = (size_t)(end - p + 1);
	}
	else {
		end = strchr(p, ':');
		if (end) {
			len = (size_t)(end - p);
		}
		else {
			len = strlen(p);
		}
	}

	if (len == 0 || len >= host_sz) {
		return EINVAL;
	}
	memcpy(host, p, len);
	host[len] = '\0';
	return 0;
}

/**
 * Split sip_user into user + domain. If sip_user has no '@', domain comes
 * from the host of sip_server.
 */
static int omnix_parse_user_domain(const omnix_config_t *config,
				   char *user, size_t user_sz,
				   char *domain, size_t domain_sz)
{
	const char *sip_user;
	const char *at;
	size_t ulen;
	size_t dlen;
	int err;

	if (!config || !user || !domain) {
		return EINVAL;
	}

	sip_user = config->sip_user;
	if (!sip_user || !sip_user[0]) {
		return EINVAL;
	}

	at = strchr(sip_user, '@');
	if (at) {
		ulen = (size_t)(at - sip_user);
		dlen = strlen(at + 1);
		if (ulen == 0 || ulen >= user_sz || dlen == 0 ||
		    dlen >= domain_sz) {
			return EINVAL;
		}
		memcpy(user, sip_user, ulen);
		user[ulen] = '\0';
		memcpy(domain, at + 1, dlen);
		domain[dlen] = '\0';
		return 0;
	}

	if (strlen(sip_user) >= user_sz) {
		return EINVAL;
	}
	str_ncpy(user, sip_user, user_sz);
	err = omnix_sip_host_from_server(config->sip_server, domain,
					 domain_sz);
	return err;
}

static int omnix_build_aor(const omnix_config_t *config,
			   char *aor, size_t aor_sz)
{
	char user[OMNIX_USER_MAX];
	char domain[OMNIX_HOST_MAX];
	const char *dname;
	int n;
	int err;

	err = omnix_parse_user_domain(config, user, sizeof(user),
				      domain, sizeof(domain));
	if (err) {
		return err;
	}

	dname = config->display_name;
	if (dname && dname[0] != '\0') {
		n = re_snprintf(aor, aor_sz,
				"\"%s\" <sip:%s@%s;transport=tls>",
				dname, user, domain);
	}
	else {
		n = re_snprintf(aor, aor_sz,
				"<sip:%s@%s;transport=tls>",
				user, domain);
	}

	if (n < 0 || (size_t)n >= aor_sz) {
		return ENOMEM;
	}

	/* Hard guard: never allow ;auth_pass= into a loggable AOR. */
	if (strstr(aor, "auth_pass") != NULL) {
		return EPROTO;
	}
	if (config->sip_password && config->sip_password[0] != '\0' &&
	    strstr(aor, config->sip_password) != NULL) {
		return EPROTO;
	}

	return 0;
}

omnix_error_t omnix_account_setup(const omnix_config_t *config)
{
	struct omnix_state *st;
	struct ua *ua = NULL;
	struct account *acc;
	char aor[OMNIX_AOR_MAX];
	char user[OMNIX_USER_MAX];
	char domain[OMNIX_HOST_MAX];
	const char *auth_user;
	char *pw_copy = NULL;
	int err;
	omnix_error_t oerr = OMNIX_ERR_OK;

	if (!config) {
		return OMNIX_ERR_INVALID_CONFIG;
	}

	st = omnix_state_get();
	if (!st) {
		return OMNIX_ERR_INTERNAL;
	}

	if (st->ua) {
		return OMNIX_ERR_INVALID_STATE;
	}

	err = omnix_build_aor(config, aor, sizeof(aor));
	if (err) {
		return OMNIX_ERR_INVALID_CONFIG;
	}

	err = omnix_parse_user_domain(config, user, sizeof(user),
				      domain, sizeof(domain));
	if (err) {
		return OMNIX_ERR_INVALID_CONFIG;
	}

	auth_user = (config->auth_user && config->auth_user[0] != '\0')
			    ? config->auth_user
			    : user;

	/*
	 * Password handling (Issue #1 §26): copy caller-owned sip_password
	 * into Omnix-owned buffer, pass to account_set_auth_pass, then wipe
	 * ONLY the Omnix-owned copy. Never write into config->sip_password.
	 * Never put the password into the AOR (no ;auth_pass=).
	 */
	if (config->sip_password && config->sip_password[0] != '\0') {
		pw_copy = omnix_password_dup(config->sip_password);
		if (!pw_copy) {
			return OMNIX_ERR_INTERNAL;
		}
		omnix_log_filter_set_secret(pw_copy);
	}

	g_codec_missing_warned = false;

	re_thread_enter();

	/* dtls_srtp must be loaded before account_set_mediaenc. */
	err = module_preload("dtls_srtp");
	if (err && err != EALREADY) {
		oerr = OMNIX_ERR_INITIALIZATION;
		goto out_leave;
	}

	/* SDK-027: G.711 (PCMU/PCMA) mandatory baseline; Opus via SDK-067. */
	err = module_preload("g711");
	if (err && err != EALREADY) {
		oerr = OMNIX_ERR_INITIALIZATION;
		goto out_leave;
	}

	/*
	 * ua_alloc → account_alloc internally from the AOR (no password).
	 * Auth and mediaenc are set on the resulting account.
	 */
	err = ua_alloc(&ua, aor);
	if (err) {
		oerr = OMNIX_ERR_INITIALIZATION;
		goto out_leave;
	}

	acc = ua_account(ua);
	if (!acc) {
		mem_deref(ua);
		ua = NULL;
		oerr = OMNIX_ERR_INTERNAL;
		goto out_leave;
	}

	err = account_set_auth_user(acc, auth_user);
	if (err) {
		mem_deref(ua);
		ua = NULL;
		oerr = OMNIX_ERR_INITIALIZATION;
		goto out_leave;
	}

	if (pw_copy) {
		err = account_set_auth_pass(acc, pw_copy);
		if (err) {
			mem_deref(ua);
			ua = NULL;
			oerr = OMNIX_ERR_INITIALIZATION;
			goto out_leave;
		}
	}

	err = account_set_mediaenc(acc, "dtls_srtp");
	if (err) {
		mem_deref(ua);
		ua = NULL;
		oerr = OMNIX_ERR_INITIALIZATION;
		goto out_leave;
	}
	/*
	 * SDK-026: mediaenc is always dtls_srtp (MVP MUST). enable_srtp=false
	 * still ends here after a WARNING in omnix_init — clear RTP forbidden.
	 */

	/*
	 * SDK-027: codec preference from omnix_config_t.codecs (default
	 * "opus,pcmu,pcma"). Missing codecs (Opus until SDK-067) → WARNING;
	 * if none remain → INVALID_CONFIG.
	 */
	oerr = omnix_account_apply_codecs(acc, config->codecs);
	if (oerr != OMNIX_ERR_OK) {
		mem_deref(ua);
		ua = NULL;
		goto out_leave;
	}

	/*
	 * Outbound proxy from sip_server (SDK-012 deferred → SDK-013).
	 * REGISTER is sent to this URI; AOR domain may differ.
	 */
	if (config->sip_server && config->sip_server[0] != '\0') {
		err = account_set_outbound(acc, config->sip_server, 0);
		if (err) {
			mem_deref(ua);
			ua = NULL;
			oerr = OMNIX_ERR_INITIALIZATION;
			goto out_leave;
		}
	}

	st->ua = ua;
	ua = NULL;
	/* Retain the Omnix-built AOR for tests (never contains password). */
	str_ncpy(st->aor_built, aor, sizeof(st->aor_built));

out_leave:
	re_thread_leave();

	if (pw_copy) {
		omnix_password_wipe_free(pw_copy);
		pw_copy = NULL;
	}

	return oerr;
}

void omnix_account_teardown(void)
{
	struct omnix_state *st = omnix_state_get();

	/*
	 * UA lives on uag_list; ua_close() / list_flush frees it. Drop our
	 * non-owning pointer only — do not mem_deref here (would race with
	 * ua_stop_all on the re thread during shutdown).
	 */
	if (st) {
		st->ua = NULL;
		st->aor_built[0] = '\0';
	}
}

/**
 * Unload Menc modules after re_main has stopped and before baresip_close.
 * Required so the next baresip_init + module_preload can re-register menc.
 */
void omnix_account_unload_modules(void)
{
	module_unload("g711");
	module_unload("dtls_srtp");
}

const char *omnix_test_account_aor(void)
{
	struct omnix_state *st = omnix_state_get();
	struct account *acc;

	if (!st || !st->ua) {
		return NULL;
	}
	acc = ua_account(st->ua);
	return acc ? account_aor(acc) : NULL;
}

const char *omnix_test_account_aor_built(void)
{
	struct omnix_state *st = omnix_state_get();

	if (!st || st->aor_built[0] == '\0') {
		return NULL;
	}
	return st->aor_built;
}

int omnix_test_account_has_tls_transport(void)
{
	struct omnix_state *st = omnix_state_get();
	struct account *acc;
	struct uri *uri;
	struct pl name;
	struct pl val;

	if (!st || !st->ua) {
		return 0;
	}
	acc = ua_account(st->ua);
	if (!acc) {
		return 0;
	}
	uri = account_luri(acc);
	if (!uri) {
		return 0;
	}
	pl_set_str(&name, "transport");
	if (0 != uri_param_get(&uri->params, &name, &val)) {
		return 0;
	}
	return 0 == pl_strcasecmp(&val, "tls");
}

const char *omnix_test_account_mediaenc(void)
{
	struct omnix_state *st = omnix_state_get();
	struct account *acc;

	if (!st || !st->ua) {
		return NULL;
	}
	acc = ua_account(st->ua);
	return acc ? account_mediaenc(acc) : NULL;
}

int omnix_test_menc_dtls_srtp_present(void)
{
	struct omnix_state *st = omnix_state_get();
	const struct menc *m;

	if (!st || !st->initialized) {
		return -1;
	}
	m = menc_find(baresip_mencl(), "dtls_srtp");
	return m ? 1 : 0;
}

const char *omnix_test_account_auth_user(void)
{
	struct omnix_state *st = omnix_state_get();
	struct account *acc;

	if (!st || !st->ua) {
		return NULL;
	}
	acc = ua_account(st->ua);
	return acc ? account_auth_user(acc) : NULL;
}

const char *omnix_test_account_display_name(void)
{
	struct omnix_state *st = omnix_state_get();
	struct account *acc;

	if (!st || !st->ua) {
		return NULL;
	}
	acc = ua_account(st->ua);
	return acc ? account_display_name(acc) : NULL;
}

const char *omnix_test_account_outbound(void)
{
	struct omnix_state *st = omnix_state_get();
	struct account *acc;

	if (!st || !st->ua) {
		return NULL;
	}
	acc = ua_account(st->ua);
	return acc ? account_outbound(acc, 0) : NULL;
}

unsigned omnix_test_account_codec_count(void)
{
	struct omnix_state *st = omnix_state_get();
	struct account *acc;
	struct list *acl;

	if (!st || !st->ua) {
		return 0;
	}
	acc = ua_account(st->ua);
	if (!acc) {
		return 0;
	}
	acl = account_aucodecl(acc);
	return acl ? (unsigned)list_count(acl) : 0;
}

const char *omnix_test_account_codec_name(unsigned idx)
{
	struct omnix_state *st = omnix_state_get();
	struct account *acc;
	struct list *acl;
	struct le *le;
	unsigned i = 0;

	if (!st || !st->ua) {
		return NULL;
	}
	acc = ua_account(st->ua);
	if (!acc) {
		return NULL;
	}
	acl = account_aucodecl(acc);
	if (!acl) {
		return NULL;
	}
	for (le = list_head(acl); le; le = le->next) {
		const struct aucodec *ac = le->data;

		if (i == idx) {
			return ac ? ac->name : NULL;
		}
		++i;
	}
	return NULL;
}

int omnix_test_aucodec_g711_present(void)
{
	struct omnix_state *st = omnix_state_get();
	const struct aucodec *pcmu;
	const struct aucodec *pcma;

	if (!st || !st->initialized) {
		return -1;
	}
	pcmu = aucodec_find(baresip_aucodecl(), "PCMU", 8000, 1);
	pcma = aucodec_find(baresip_aucodecl(), "PCMA", 8000, 1);
	return (pcmu && pcma) ? 1 : 0;
}

int omnix_test_warned_codec_missing(void)
{
	return g_codec_missing_warned ? 1 : 0;
}
