/*
 * Omnix Voice — Android shared-library anchor (SDK-030).
 *
 * Keeps a live reference to the C facade so --whole-archive linkage of
 * static omnix_voice/baresip is not discarded. JNI_OnLoad and method
 * bindings are added in SDK-031.
 *
 * No credentials, hostnames, or secrets in this file.
 */

#include "omnix_voice/omnix_voice.h"

/* Touch a public symbol so LTO/GC cannot drop the facade from the .so. */
omnix_error_t omnixvoice_android_anchor(void)
{
	(void)omnix_get_reg_state();
	return OMNIX_ERR_OK;
}
