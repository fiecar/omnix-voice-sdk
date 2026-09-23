/**
 * Omnix Voice — Android JNI bridge (SDK-031).
 *
 * Connects Kotlin (com.omnix.voice.internal.OmnixNative) to the Omnix C
 * facade only. No Baresip / re types in this header.
 *
 * No credentials, hostnames, or secrets in this file.
 */
#ifndef OMNIX_JNI_H
#define OMNIX_JNI_H

#include <jni.h>

#ifdef __cplusplus
extern "C" {
#endif

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *reserved);
JNIEXPORT void JNICALL JNI_OnUnload(JavaVM *vm, void *reserved);

#ifdef __cplusplus
}
#endif

#endif /* OMNIX_JNI_H */
