/**
 * Omnix Voice — log redaction + Baresip log handler (SDK-010).
 */
#include "omnix_internal.h"

#include <re.h>
#include <baresip.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char *g_secret;
static struct log g_log;
static bool g_log_registered;
static char g_last_log[1024];

void omnix_test_reset_last_log(void)
{
	g_last_log[0] = '\0';
}

const char *omnix_test_last_log(void)
{
	return g_last_log;
}

int omnix_log_redact_to(const char *msg, char *out, size_t out_len)
{
	size_t secret_len;
	const char *src;
	char *dst;
	size_t remaining;

	if (!msg || !out || out_len == 0) {
		return -1;
	}

	if (!g_secret || g_secret[0] == '\0') {
		snprintf(out, out_len, "%s", msg);
		return 0;
	}

	secret_len = strlen(g_secret);
	src = msg;
	dst = out;
	remaining = out_len - 1;

	while (*src && remaining > 0) {
		if (secret_len > 0 &&
		    strncmp(src, g_secret, secret_len) == 0) {
			const char *repl = "[REDACTED]";
			size_t repl_len = strlen(repl);
			if (repl_len > remaining) {
				repl_len = remaining;
			}
			memcpy(dst, repl, repl_len);
			dst += repl_len;
			remaining -= repl_len;
			src += secret_len;
		}
		else {
			*dst++ = *src++;
			remaining--;
		}
	}
	*dst = '\0';
	return 0;
}

void omnix_log_filter_set_secret(const char *secret)
{
	omnix_password_wipe_free(g_secret);
	g_secret = NULL;
	if (secret && secret[0] != '\0') {
		g_secret = omnix_password_dup(secret);
	}
}

void omnix_log_filter_clear(void)
{
	omnix_password_wipe_free(g_secret);
	g_secret = NULL;
}

static void omnix_log_h(uint32_t level, const char *msg)
{
	char redacted[1024];
	(void)level;

	if (!msg) {
		return;
	}
	if (omnix_log_redact_to(msg, redacted, sizeof(redacted)) != 0) {
		return;
	}
	snprintf(g_last_log, sizeof(g_last_log), "%s", redacted);
	/* Never print secrets: always emit the redacted form. */
	fputs(redacted, stderr);
	fputc('\n', stderr);
}

void omnix_log_handler_register(void)
{
	if (g_log_registered) {
		return;
	}
	memset(&g_log, 0, sizeof(g_log));
	g_log.h = omnix_log_h;
	log_register_handler(&g_log);
	g_log_registered = true;
}

void omnix_log_handler_unregister(void)
{
	if (!g_log_registered) {
		return;
	}
	log_unregister_handler(&g_log);
	g_log_registered = false;
	omnix_log_filter_clear();
}

void omnix_test_emit_via_log_path(const char *msg)
{
	/* Exercise the same Baresip log dispatch path used at runtime. */
	info("%s", msg ? msg : "");
}

char *omnix_password_dup(const char *src)
{
	size_t n;
	char *copy;

	if (!src) {
		return NULL;
	}
	n = strlen(src);
	copy = (char *)malloc(n + 1);
	if (!copy) {
		return NULL;
	}
	memcpy(copy, src, n + 1);
	return copy;
}

void omnix_password_wipe_free(char *pw)
{
	volatile char *p;
	size_t len;

	if (!pw) {
		return;
	}
	len = strlen(pw);
	p = (volatile char *)pw;
	while (len--) {
		*p++ = 0;
	}
	free(pw);
}
