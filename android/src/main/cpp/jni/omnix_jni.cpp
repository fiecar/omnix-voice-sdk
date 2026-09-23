/**
 * Omnix Voice — Android JNI bridge (SDK-031).
 *
 * Critical rules (Issue #2):
 * - JNI_OnLoad stores JavaVM*; JNI_OnUnload deletes global refs.
 * - GetStringUTFChars / ReleaseStringUTFChars paired on ALL paths.
 * - AttachCurrentThread / DetachCurrentThread paired for C→Kotlin callbacks.
 * - Calls Omnix C facade only (re locking is inside the facade).
 *
 * Placeholders only in comments; no secrets.
 */

#include "omnix_jni.h"

#include "omnix_voice/omnix_voice.h"

#include <android/log.h>

#include <cstring>
#include <mutex>
#include <string>

#define OMNIX_JNI_LOG_TAG "OmnixVoiceJNI"

namespace {

JavaVM *g_vm = nullptr;
std::mutex g_cb_mu;
jobject g_callback = nullptr; /* global ref to OmnixNativeCallback */
jmethodID g_mid_on_reg = nullptr;
jmethodID g_mid_on_call = nullptr;
jmethodID g_mid_on_error = nullptr;

/* Owned UTF-8 copies for omnix_config_t pointer lifetime across init. */
struct OwnedConfigStrings {
	std::string sip_server;
	std::string sip_user;
	std::string auth_user;
	std::string sip_password;
	std::string display_name;
	std::string stun_server;
	std::string codecs;
};

OwnedConfigStrings g_cfg_strings;

class JniUtfChars {
public:
	JniUtfChars(JNIEnv *env, jstring js)
		: env_(env), js_(js), utf_(nullptr)
	{
		if (js_) {
			utf_ = env_->GetStringUTFChars(js_, nullptr);
		}
	}

	~JniUtfChars()
	{
		if (js_ && utf_) {
			env_->ReleaseStringUTFChars(js_, utf_);
		}
	}

	JniUtfChars(const JniUtfChars &) = delete;
	JniUtfChars &operator=(const JniUtfChars &) = delete;

	const char *c_str() const { return utf_; }
	bool ok() const { return js_ == nullptr || utf_ != nullptr; }

private:
	JNIEnv *env_;
	jstring js_;
	const char *utf_;
};

JNIEnv *omnix_jni_get_env(bool *attached)
{
	*attached = false;
	if (!g_vm) {
		return nullptr;
	}
	JNIEnv *env = nullptr;
	jint st = g_vm->GetEnv(reinterpret_cast<void **>(&env), JNI_VERSION_1_6);
	if (st == JNI_EDETACHED) {
		if (g_vm->AttachCurrentThread(&env, nullptr) != 0) {
			return nullptr;
		}
		*attached = true;
		return env;
	}
	if (st != JNI_OK) {
		return nullptr;
	}
	return env;
}

void omnix_jni_detach_if_needed(bool attached)
{
	if (attached && g_vm) {
		g_vm->DetachCurrentThread();
	}
}

void omnix_jni_clear_callback_unlocked(JNIEnv *env)
{
	if (g_callback && env) {
		env->DeleteGlobalRef(g_callback);
	}
	g_callback = nullptr;
	g_mid_on_reg = nullptr;
	g_mid_on_call = nullptr;
	g_mid_on_error = nullptr;
}

void omnix_jni_on_reg_state(omnix_reg_state_t state, int sip_code,
			    const char *reason, void *ctx)
{
	(void)ctx;
	bool attached = false;
	JNIEnv *env = omnix_jni_get_env(&attached);
	if (!env) {
		return;
	}

	jobject cb = nullptr;
	jmethodID mid = nullptr;
	{
		std::lock_guard<std::mutex> lock(g_cb_mu);
		cb = g_callback;
		mid = g_mid_on_reg;
	}
	if (cb && mid) {
		jstring jreason =
			reason ? env->NewStringUTF(reason) : nullptr;
		env->CallVoidMethod(cb, mid, static_cast<jint>(state),
				    static_cast<jint>(sip_code), jreason);
		if (env->ExceptionCheck()) {
			env->ExceptionDescribe();
			env->ExceptionClear();
		}
		if (jreason) {
			env->DeleteLocalRef(jreason);
		}
	}
	omnix_jni_detach_if_needed(attached);
}

void omnix_jni_on_call_event(omnix_call_state_t state,
			     const omnix_call_info_t *call, void *ctx)
{
	(void)ctx;
	bool attached = false;
	JNIEnv *env = omnix_jni_get_env(&attached);
	if (!env || !call) {
		omnix_jni_detach_if_needed(attached);
		return;
	}

	jobject cb = nullptr;
	jmethodID mid = nullptr;
	{
		std::lock_guard<std::mutex> lock(g_cb_mu);
		cb = g_callback;
		mid = g_mid_on_call;
	}
	if (cb && mid) {
		jstring jid = env->NewStringUTF(call->call_id);
		jstring juri = env->NewStringUTF(call->peer_uri);
		jstring jname = env->NewStringUTF(call->peer_display_name);
		env->CallVoidMethod(cb, mid, static_cast<jint>(state), jid,
				    juri, jname,
				    static_cast<jboolean>(call->is_outgoing),
				    static_cast<jboolean>(call->is_muted),
				    static_cast<jboolean>(call->is_on_hold));
		if (env->ExceptionCheck()) {
			env->ExceptionDescribe();
			env->ExceptionClear();
		}
		if (jid) {
			env->DeleteLocalRef(jid);
		}
		if (juri) {
			env->DeleteLocalRef(juri);
		}
		if (jname) {
			env->DeleteLocalRef(jname);
		}
	}
	omnix_jni_detach_if_needed(attached);
}

void omnix_jni_on_error(omnix_error_t err, const char *detail, void *ctx)
{
	(void)ctx;
	bool attached = false;
	JNIEnv *env = omnix_jni_get_env(&attached);
	if (!env) {
		return;
	}

	jobject cb = nullptr;
	jmethodID mid = nullptr;
	{
		std::lock_guard<std::mutex> lock(g_cb_mu);
		cb = g_callback;
		mid = g_mid_on_error;
	}
	if (cb && mid) {
		jstring jdetail =
			detail ? env->NewStringUTF(detail) : nullptr;
		env->CallVoidMethod(cb, mid, static_cast<jint>(err), jdetail);
		if (env->ExceptionCheck()) {
			env->ExceptionDescribe();
			env->ExceptionClear();
		}
		if (jdetail) {
			env->DeleteLocalRef(jdetail);
		}
	}
	omnix_jni_detach_if_needed(attached);
}

static std::string jstring_to_owned(JNIEnv *env, jstring js)
{
	if (!js) {
		return {};
	}
	JniUtfChars utf(env, js);
	if (!utf.ok() || !utf.c_str()) {
		return {};
	}
	return std::string(utf.c_str());
}

} /* namespace */

extern "C" {

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *reserved)
{
	(void)reserved;
	g_vm = vm;
	JNIEnv *env = nullptr;
	if (vm->GetEnv(reinterpret_cast<void **>(&env), JNI_VERSION_1_6) !=
	    JNI_OK) {
		return JNI_ERR;
	}
	__android_log_print(ANDROID_LOG_INFO, OMNIX_JNI_LOG_TAG,
			    "JNI_OnLoad OK");
	return JNI_VERSION_1_6;
}

JNIEXPORT void JNICALL JNI_OnUnload(JavaVM *vm, void *reserved)
{
	(void)reserved;
	JNIEnv *env = nullptr;
	if (vm->GetEnv(reinterpret_cast<void **>(&env), JNI_VERSION_1_6) ==
	    JNI_OK) {
		std::lock_guard<std::mutex> lock(g_cb_mu);
		omnix_jni_clear_callback_unlocked(env);
	}
	g_vm = nullptr;
	g_cfg_strings = OwnedConfigStrings{};
	__android_log_print(ANDROID_LOG_INFO, OMNIX_JNI_LOG_TAG,
			    "JNI_OnUnload OK");
}

/*
 * Java_com_omnix_voice_internal_OmnixNative_*
 * Class: com.omnix.voice.internal.OmnixNative (SDK-031 minimal / SDK-032).
 */

JNIEXPORT jint JNICALL
Java_com_omnix_voice_internal_OmnixNative_nativeInit(
	JNIEnv *env, jclass /*clazz*/, jstring sipServer, jstring sipUser,
	jstring authUser, jstring sipPassword, jstring displayName,
	jstring stunServer, jboolean verifyCert, jboolean enableSrtp,
	jstring codecs)
{
	g_cfg_strings.sip_server = jstring_to_owned(env, sipServer);
	g_cfg_strings.sip_user = jstring_to_owned(env, sipUser);
	g_cfg_strings.auth_user = jstring_to_owned(env, authUser);
	g_cfg_strings.sip_password = jstring_to_owned(env, sipPassword);
	g_cfg_strings.display_name = jstring_to_owned(env, displayName);
	g_cfg_strings.stun_server = jstring_to_owned(env, stunServer);
	g_cfg_strings.codecs = jstring_to_owned(env, codecs);

	omnix_config_t cfg{};
	cfg.sip_server = g_cfg_strings.sip_server.empty()
				 ? nullptr
				 : g_cfg_strings.sip_server.c_str();
	cfg.sip_user = g_cfg_strings.sip_user.empty()
			       ? nullptr
			       : g_cfg_strings.sip_user.c_str();
	cfg.auth_user = g_cfg_strings.auth_user.empty()
				? nullptr
				: g_cfg_strings.auth_user.c_str();
	cfg.sip_password = g_cfg_strings.sip_password.empty()
				   ? nullptr
				   : g_cfg_strings.sip_password.c_str();
	cfg.display_name = g_cfg_strings.display_name.empty()
				   ? nullptr
				   : g_cfg_strings.display_name.c_str();
	cfg.stun_server = g_cfg_strings.stun_server.empty()
				  ? nullptr
				  : g_cfg_strings.stun_server.c_str();
	cfg.verify_tls_cert = verifyCert == JNI_TRUE;
	cfg.enable_srtp = enableSrtp == JNI_TRUE;
	cfg.codecs = g_cfg_strings.codecs.empty()
			     ? nullptr
			     : g_cfg_strings.codecs.c_str();
	cfg.on_reg_state = omnix_jni_on_reg_state;
	cfg.on_call_event = omnix_jni_on_call_event;
	cfg.on_error = omnix_jni_on_error;
	cfg.ctx = nullptr;

	omnix_error_t err = omnix_init(&cfg);

	/* Wipe local password copy after init (facade owns its wipe separately). */
	if (!g_cfg_strings.sip_password.empty()) {
		volatile char *p =
			reinterpret_cast<volatile char *>(
				&g_cfg_strings.sip_password[0]);
		size_t n = g_cfg_strings.sip_password.size();
		while (n--) {
			*p++ = 0;
		}
		g_cfg_strings.sip_password.clear();
		g_cfg_strings.sip_password.shrink_to_fit();
	}

	return static_cast<jint>(err);
}

JNIEXPORT void JNICALL
Java_com_omnix_voice_internal_OmnixNative_nativeShutdown(JNIEnv * /*env*/,
							 jclass /*clazz*/)
{
	omnix_shutdown();
	g_cfg_strings = OwnedConfigStrings{};
}

JNIEXPORT jint JNICALL
Java_com_omnix_voice_internal_OmnixNative_nativeRegister(JNIEnv * /*env*/,
							 jclass /*clazz*/)
{
	return static_cast<jint>(omnix_register());
}

JNIEXPORT void JNICALL
Java_com_omnix_voice_internal_OmnixNative_nativeUnregister(JNIEnv * /*env*/,
							   jclass /*clazz*/)
{
	omnix_unregister();
}

JNIEXPORT jstring JNICALL
Java_com_omnix_voice_internal_OmnixNative_nativeMakeCall(JNIEnv *env,
							 jclass /*clazz*/,
							 jstring destination)
{
	JniUtfChars dest(env, destination);
	if (!dest.ok()) {
		return nullptr;
	}
	if (!dest.c_str() || !dest.c_str()[0]) {
		return nullptr;
	}

	char call_id[128];
	call_id[0] = '\0';
	omnix_error_t err =
		omnix_call_make(dest.c_str(), call_id, sizeof(call_id));
	if (err != OMNIX_ERR_OK) {
		return nullptr;
	}
	return env->NewStringUTF(call_id);
}

JNIEXPORT jint JNICALL
Java_com_omnix_voice_internal_OmnixNative_nativeAnswerCall(JNIEnv *env,
							   jclass /*clazz*/,
							   jstring callId)
{
	JniUtfChars id(env, callId);
	if (!id.ok() || !id.c_str()) {
		return static_cast<jint>(OMNIX_ERR_INVALID_STATE);
	}
	return static_cast<jint>(omnix_call_answer(id.c_str()));
}

JNIEXPORT jint JNICALL
Java_com_omnix_voice_internal_OmnixNative_nativeRejectCall(JNIEnv *env,
							   jclass /*clazz*/,
							   jstring callId)
{
	JniUtfChars id(env, callId);
	if (!id.ok() || !id.c_str()) {
		return static_cast<jint>(OMNIX_ERR_INVALID_STATE);
	}
	return static_cast<jint>(omnix_call_reject(id.c_str()));
}

JNIEXPORT jint JNICALL
Java_com_omnix_voice_internal_OmnixNative_nativeHangupCall(JNIEnv *env,
							   jclass /*clazz*/,
							   jstring callId)
{
	JniUtfChars id(env, callId);
	if (!id.ok() || !id.c_str()) {
		return static_cast<jint>(OMNIX_ERR_INVALID_STATE);
	}
	return static_cast<jint>(omnix_call_hangup(id.c_str()));
}

JNIEXPORT jint JNICALL
Java_com_omnix_voice_internal_OmnixNative_nativeHoldCall(JNIEnv *env,
							 jclass /*clazz*/,
							 jstring callId)
{
	JniUtfChars id(env, callId);
	if (!id.ok() || !id.c_str()) {
		return static_cast<jint>(OMNIX_ERR_INVALID_STATE);
	}
	return static_cast<jint>(omnix_call_hold(id.c_str()));
}

JNIEXPORT jint JNICALL
Java_com_omnix_voice_internal_OmnixNative_nativeResumeCall(JNIEnv *env,
							   jclass /*clazz*/,
							   jstring callId)
{
	JniUtfChars id(env, callId);
	if (!id.ok() || !id.c_str()) {
		return static_cast<jint>(OMNIX_ERR_INVALID_STATE);
	}
	return static_cast<jint>(omnix_call_resume(id.c_str()));
}

JNIEXPORT jint JNICALL
Java_com_omnix_voice_internal_OmnixNative_nativeSetMuted(JNIEnv *env,
							 jclass /*clazz*/,
							 jstring callId,
							 jboolean mute)
{
	JniUtfChars id(env, callId);
	if (!id.ok() || !id.c_str()) {
		return static_cast<jint>(OMNIX_ERR_INVALID_STATE);
	}
	return static_cast<jint>(
		omnix_call_set_mute(id.c_str(), mute == JNI_TRUE));
}

JNIEXPORT jint JNICALL
Java_com_omnix_voice_internal_OmnixNative_nativeSetSpeaker(JNIEnv * /*env*/,
							   jclass /*clazz*/,
							   jboolean enable)
{
	return static_cast<jint>(
		omnix_call_set_speaker(enable == JNI_TRUE));
}

JNIEXPORT jint JNICALL
Java_com_omnix_voice_internal_OmnixNative_nativeSendDTMF(JNIEnv *env,
							 jclass /*clazz*/,
							 jstring callId,
							 jchar digit)
{
	JniUtfChars id(env, callId);
	if (!id.ok() || !id.c_str()) {
		return static_cast<jint>(OMNIX_ERR_INVALID_STATE);
	}
	char d = static_cast<char>(digit & 0x7f);
	return static_cast<jint>(omnix_call_send_dtmf(id.c_str(), d));
}

JNIEXPORT void JNICALL
Java_com_omnix_voice_internal_OmnixNative_nativeSetCallback(
	JNIEnv *env, jclass /*clazz*/, jobject callback)
{
	std::lock_guard<std::mutex> lock(g_cb_mu);
	omnix_jni_clear_callback_unlocked(env);
	if (!callback) {
		return;
	}

	jobject global = env->NewGlobalRef(callback);
	if (!global) {
		return;
	}

	jclass cls = env->GetObjectClass(callback);
	if (!cls) {
		env->DeleteGlobalRef(global);
		return;
	}

	jmethodID mid_reg = env->GetMethodID(
		cls, "onRegistrationStateChanged",
		"(IILjava/lang/String;)V");
	jmethodID mid_call = env->GetMethodID(
		cls, "onCallEvent",
		"(ILjava/lang/String;Ljava/lang/String;Ljava/lang/String;ZZZ)V");
	jmethodID mid_err =
		env->GetMethodID(cls, "onError", "(ILjava/lang/String;)V");
	env->DeleteLocalRef(cls);

	if (!mid_reg || !mid_call || !mid_err) {
		if (env->ExceptionCheck()) {
			env->ExceptionClear();
		}
		env->DeleteGlobalRef(global);
		__android_log_print(ANDROID_LOG_ERROR, OMNIX_JNI_LOG_TAG,
				    "nativeSetCallback: missing methods");
		return;
	}

	g_callback = global;
	g_mid_on_reg = mid_reg;
	g_mid_on_call = mid_call;
	g_mid_on_error = mid_err;
}

} /* extern "C" */
