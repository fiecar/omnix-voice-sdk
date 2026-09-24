/**
 * Omnix Voice — Objective-C bridge implementation (SDK-040).
 *
 * Calls Omnix C facade only. Dispatches all callbacks to the main queue.
 * Never writes into caller-owned password memory; omnix_init copies + wipes.
 *
 * Placeholders only; no credentials or secrets.
 */

#import "OmnixVoiceBridge.h"

#include "omnix_voice/omnix_voice.h"

#include <string.h>

NSErrorDomain const OmnixVoiceBridgeErrorDomain = @"com.omnix.voice.bridge";

@interface OmnixVoiceBridgeCallInfo ()
- (instancetype)initWithCallId:(NSString *)callId
                       peerUri:(NSString *)peerUri
               peerDisplayName:(NSString *)peerDisplayName
                         state:(OmnixBridgeCallState)state
                    isOutgoing:(BOOL)isOutgoing
                       isMuted:(BOOL)isMuted
                      isOnHold:(BOOL)isOnHold;
@end

@implementation OmnixVoiceBridgeConfig

- (instancetype)init {
    self = [super init];
    if (self) {
        _verifyCert = YES;
        _enableSrtp = YES;
    }
    return self;
}

- (NSString *)description {
    return [NSString
        stringWithFormat:
            @"OmnixVoiceBridgeConfig(sipServer=%@, sipUser=%@, authUser=%@, "
            @"sipPassword=[REDACTED], displayName=%@, stunServer=%@, "
            @"verifyCert=%d, enableSrtp=%d, codecs=%@)",
            self.sipServer, self.sipUser, self.authUser, self.displayName,
            self.stunServer, (int)self.verifyCert, (int)self.enableSrtp,
            self.codecs];
}

@end

@implementation OmnixVoiceBridgeCallInfo

- (instancetype)initWithCallId:(NSString *)callId
                       peerUri:(NSString *)peerUri
               peerDisplayName:(NSString *)peerDisplayName
                         state:(OmnixBridgeCallState)state
                    isOutgoing:(BOOL)isOutgoing
                       isMuted:(BOOL)isMuted
                      isOnHold:(BOOL)isOnHold {
    self = [super init];
    if (self) {
        _callId = [callId copy] ?: @"";
        _peerUri = [peerUri copy] ?: @"";
        _peerDisplayName = [peerDisplayName copy] ?: @"";
        _state = state;
        _isOutgoing = isOutgoing;
        _isMuted = isMuted;
        _isOnHold = isOnHold;
    }
    return self;
}

@end

@interface OmnixVoiceBridge () {
    NSMutableDictionary<NSString *, OmnixVoiceBridgeCallInfo *> *_calls;
    BOOL _initialized;
    OmnixBridgeRegistrationState _registrationState;
}
@end

/* C callbacks → ObjC (ctx is the OmnixVoiceBridge instance). */
static void omnix_bridge_on_reg(omnix_reg_state_t state, int sip_code,
                                const char *reason, void *ctx);
static void omnix_bridge_on_call(omnix_call_state_t state,
                                 const omnix_call_info_t *call, void *ctx);
static void omnix_bridge_on_error(omnix_error_t err, const char *detail,
                                  void *ctx);

@implementation OmnixVoiceBridge

+ (OmnixVoiceBridge *)sharedBridge {
    static OmnixVoiceBridge *bridge;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      bridge = [[OmnixVoiceBridge alloc] init];
    });
    return bridge;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _calls = [NSMutableDictionary dictionary];
        _initialized = NO;
        _registrationState = OmnixBridgeRegistrationStateUninitialized;
    }
    return self;
}

- (BOOL)isInitialized {
    return _initialized;
}

- (OmnixBridgeRegistrationState)registrationState {
    @synchronized(self) {
        if (_initialized) {
            _registrationState =
                (OmnixBridgeRegistrationState)omnix_get_reg_state();
        }
        return _registrationState;
    }
}

- (NSError *)errorWithCode:(OmnixBridgeErrorCode)code
                    detail:(nullable NSString *)detail {
    NSString *msg =
        detail.length > 0
            ? [NSString stringWithFormat:@"OmnixVoiceBridge error: %ld — %@",
                                         (long)code, detail]
            : [NSString stringWithFormat:@"OmnixVoiceBridge error: %ld",
                                         (long)code];
    return [NSError errorWithDomain:OmnixVoiceBridgeErrorDomain
                               code:(NSInteger)code
                           userInfo:@{NSLocalizedDescriptionKey : msg}];
}

- (BOOL)failWithCode:(OmnixBridgeErrorCode)code
              detail:(nullable NSString *)detail
               error:(NSError *_Nullable *_Nullable)error {
    if (error) {
        *error = [self errorWithCode:code detail:detail];
    }
    return NO;
}

- (BOOL)mapNative:(omnix_error_t)rc
            error:(NSError *_Nullable *_Nullable)error {
    if (rc == OMNIX_ERR_OK) {
        return YES;
    }
    OmnixBridgeErrorCode mapped = (OmnixBridgeErrorCode)rc;
    if (mapped < OmnixBridgeErrorCodeInitialization ||
        mapped > OmnixBridgeErrorCodeInternal) {
        mapped = OmnixBridgeErrorCodeInternal;
    }
    return [self failWithCode:mapped detail:nil error:error];
}

- (BOOL)initializeWithConfig:(OmnixVoiceBridgeConfig *)config
                       error:(NSError *_Nullable *_Nullable)error {
    @synchronized(self) {
        if (_initialized) {
            return [self failWithCode:OmnixBridgeErrorCodeInvalidCallState
                               detail:@"already initialized"
                                error:error];
        }
        if (config.sipServer.length == 0 || config.sipUser.length == 0) {
            return [self failWithCode:OmnixBridgeErrorCodeInvalidConfiguration
                               detail:@"sipServer and sipUser are required"
                                error:error];
        }

        /*
         * Pass UTF-8 views into omnix_init. The C facade copies credentials
         * into Omnix-owned storage and wipes its copy; we never mutate the
         * NSString / caller-owned buffers.
         */
        omnix_config_t cfg;
        memset(&cfg, 0, sizeof(cfg));
        cfg.sip_server = config.sipServer.UTF8String;
        cfg.sip_user = config.sipUser.UTF8String;
        cfg.auth_user = config.authUser.UTF8String;
        cfg.sip_password = config.sipPassword.UTF8String;
        cfg.display_name = config.displayName.UTF8String;
        cfg.stun_server = config.stunServer.UTF8String;
        cfg.verify_tls_cert = config.verifyCert ? true : false;
        cfg.enable_srtp = config.enableSrtp ? true : false;
        cfg.audio_module = "audiounit";
        cfg.codecs = config.codecs.UTF8String;
        cfg.on_reg_state = omnix_bridge_on_reg;
        cfg.on_call_event = omnix_bridge_on_call;
        cfg.on_error = omnix_bridge_on_error;
        cfg.ctx = (__bridge void *)self;

        omnix_error_t rc = omnix_init(&cfg);
        if (rc != OMNIX_ERR_OK) {
            return [self mapNative:rc error:error];
        }

        _initialized = YES;
        _registrationState = OmnixBridgeRegistrationStateUnregistered;
        return YES;
    }
}

- (void)shutdown {
    @synchronized(self) {
        if (!_initialized) {
            return;
        }
        omnix_shutdown();
        [_calls removeAllObjects];
        _registrationState = OmnixBridgeRegistrationStateUninitialized;
        _initialized = NO;
    }
}

- (BOOL)registerWithError:(NSError *_Nullable *_Nullable)error {
    @synchronized(self) {
        if (!_initialized) {
            return [self failWithCode:OmnixBridgeErrorCodeInvalidCallState
                               detail:@"SDK not initialized"
                                error:error];
        }
        return [self mapNative:omnix_register() error:error];
    }
}

- (void)unregister {
    @synchronized(self) {
        if (!_initialized) {
            return;
        }
        omnix_unregister();
    }
}

- (BOOL)makeCall:(NSString *)destination
          callId:(NSString *_Nullable *_Nullable)callIdOut
           error:(NSError *_Nullable *_Nullable)error {
    @synchronized(self) {
        if (!_initialized) {
            return [self failWithCode:OmnixBridgeErrorCodeInvalidCallState
                               detail:@"SDK not initialized"
                                error:error];
        }
        if (destination.length == 0) {
            return [self failWithCode:OmnixBridgeErrorCodeInvalidConfiguration
                               detail:@"destination is required"
                                error:error];
        }
        char buf[128];
        memset(buf, 0, sizeof(buf));
        omnix_error_t rc =
            omnix_call_make(destination.UTF8String, buf, sizeof(buf));
        if (rc != OMNIX_ERR_OK || buf[0] == '\0') {
            if (rc == OMNIX_ERR_OK) {
                rc = OMNIX_ERR_CALL_FAILED;
            }
            return [self mapNative:rc error:error];
        }
        if (callIdOut) {
            *callIdOut = [NSString stringWithUTF8String:buf];
        }
        return YES;
    }
}

- (BOOL)answerCall:(NSString *)callId
             error:(NSError *_Nullable *_Nullable)error {
    return [self invokeCallOp:callId
                        error:error
                          op:^omnix_error_t(const char *cid) {
                            return omnix_call_answer(cid);
                          }];
}

- (BOOL)rejectCall:(NSString *)callId
             error:(NSError *_Nullable *_Nullable)error {
    return [self invokeCallOp:callId
                        error:error
                          op:^omnix_error_t(const char *cid) {
                            return omnix_call_reject(cid);
                          }];
}

- (BOOL)hangupCall:(NSString *)callId
             error:(NSError *_Nullable *_Nullable)error {
    return [self invokeCallOp:callId
                        error:error
                          op:^omnix_error_t(const char *cid) {
                            return omnix_call_hangup(cid);
                          }];
}

- (BOOL)holdCall:(NSString *)callId error:(NSError *_Nullable *_Nullable)error {
    return [self invokeCallOp:callId
                        error:error
                          op:^omnix_error_t(const char *cid) {
                            return omnix_call_hold(cid);
                          }];
}

- (BOOL)resumeCall:(NSString *)callId
             error:(NSError *_Nullable *_Nullable)error {
    return [self invokeCallOp:callId
                        error:error
                          op:^omnix_error_t(const char *cid) {
                            return omnix_call_resume(cid);
                          }];
}

- (BOOL)setMuted:(BOOL)muted
          callId:(NSString *)callId
           error:(NSError *_Nullable *_Nullable)error {
    return [self invokeCallOp:callId
                        error:error
                          op:^omnix_error_t(const char *cid) {
                            return omnix_call_set_mute(cid, muted ? true : false);
                          }];
}

- (BOOL)setSpeakerEnabled:(BOOL)enabled
                    error:(NSError *_Nullable *_Nullable)error {
    @synchronized(self) {
        if (!_initialized) {
            return [self failWithCode:OmnixBridgeErrorCodeInvalidCallState
                               detail:@"SDK not initialized"
                                error:error];
        }
        return [self mapNative:omnix_call_set_speaker(enabled ? true : false)
                         error:error];
    }
}

- (BOOL)sendDTMF:(unichar)digit
          callId:(NSString *)callId
           error:(NSError *_Nullable *_Nullable)error {
    if (digit > 127) {
        return [self failWithCode:OmnixBridgeErrorCodeInvalidConfiguration
                           detail:@"DTMF digit out of range"
                            error:error];
    }
    char d = (char)digit;
    return [self invokeCallOp:callId
                        error:error
                          op:^omnix_error_t(const char *cid) {
                            return omnix_call_send_dtmf(cid, d);
                          }];
}

- (BOOL)transferCall:(NSString *)callId
         destination:(NSString *)destination
               error:(NSError *_Nullable *_Nullable)error {
    @synchronized(self) {
        if (!_initialized) {
            return [self failWithCode:OmnixBridgeErrorCodeInvalidCallState
                               detail:@"SDK not initialized"
                                error:error];
        }
        if (callId.length == 0 || destination.length == 0) {
            return [self failWithCode:OmnixBridgeErrorCodeInvalidConfiguration
                               detail:@"callId and destination are required"
                                error:error];
        }
        return [self mapNative:omnix_call_transfer_blind(callId.UTF8String,
                                                         destination.UTF8String)
                         error:error];
    }
}

- (nullable OmnixVoiceBridgeCallInfo *)callInfoForCallId:(NSString *)callId {
    @synchronized(self) {
        if (callId.length == 0) {
            return nil;
        }
        OmnixVoiceBridgeCallInfo *cached = _calls[callId];
        if (!_initialized) {
            return cached;
        }
        /* Refresh call state from C facade when available. */
        omnix_call_state_t st = omnix_call_get_state(callId.UTF8String);
        if (!cached) {
            if (st == OMNIX_CALL_IDLE) {
                return nil;
            }
            cached = [[OmnixVoiceBridgeCallInfo alloc] initWithCallId:callId
                                                             peerUri:@""
                                                     peerDisplayName:@""
                                                               state:(OmnixBridgeCallState)st
                                                          isOutgoing:NO
                                                             isMuted:NO
                                                            isOnHold:(st == OMNIX_CALL_HELD)];
            _calls[callId] = cached;
            return cached;
        }
        if ((OmnixBridgeCallState)st != cached.state) {
            OmnixVoiceBridgeCallInfo *updated =
                [[OmnixVoiceBridgeCallInfo alloc] initWithCallId:cached.callId
                                                         peerUri:cached.peerUri
                                                 peerDisplayName:cached.peerDisplayName
                                                           state:(OmnixBridgeCallState)st
                                                      isOutgoing:cached.isOutgoing
                                                         isMuted:cached.isMuted
                                                        isOnHold:cached.isOnHold];
            _calls[callId] = updated;
            return updated;
        }
        return cached;
    }
}

- (BOOL)invokeCallOp:(NSString *)callId
               error:(NSError *_Nullable *_Nullable)error
                  op:(omnix_error_t (^)(const char *cid))op {
    @synchronized(self) {
        if (!_initialized) {
            return [self failWithCode:OmnixBridgeErrorCodeInvalidCallState
                               detail:@"SDK not initialized"
                                error:error];
        }
        if (callId.length == 0) {
            return [self failWithCode:OmnixBridgeErrorCodeInvalidConfiguration
                               detail:@"callId is required"
                                error:error];
        }
        return [self mapNative:op(callId.UTF8String) error:error];
    }
}

#pragma mark - C → ObjC (main-queue dispatch)

- (void)handleRegState:(OmnixBridgeRegistrationState)state
               sipCode:(NSInteger)sipCode
                reason:(nullable NSString *)reason {
    _registrationState = state;
    id<OmnixVoiceBridgeDelegate> del = self.delegate;
    if ([del respondsToSelector:@selector(omnixVoiceBridge:
                                        registrationStateChanged:sipCode:reason:)]) {
        [del omnixVoiceBridge:self
            registrationStateChanged:state
                             sipCode:sipCode
                              reason:reason];
    }
}

- (void)handleCallEvent:(OmnixVoiceBridgeCallInfo *)info {
    @synchronized(self) {
        _calls[info.callId] = info;
    }
    id<OmnixVoiceBridgeDelegate> del = self.delegate;
    if (info.state == OmnixBridgeCallStateIncoming) {
        if ([del respondsToSelector:@selector(omnixVoiceBridge:incomingCall:)]) {
            [del omnixVoiceBridge:self incomingCall:info];
        }
    }
    if ([del respondsToSelector:@selector(omnixVoiceBridge:callStateChanged:)]) {
        [del omnixVoiceBridge:self callStateChanged:info];
    }
}

- (void)handleError:(OmnixBridgeErrorCode)code
             detail:(nullable NSString *)detail {
    id<OmnixVoiceBridgeDelegate> del = self.delegate;
    if ([del respondsToSelector:@selector(omnixVoiceBridge:error:detail:)]) {
        [del omnixVoiceBridge:self error:code detail:detail];
    }
}

@end

static void omnix_bridge_on_reg(omnix_reg_state_t state, int sip_code,
                                const char *reason, void *ctx) {
    OmnixVoiceBridge *bridge = (__bridge OmnixVoiceBridge *)ctx;
    if (!bridge) {
        return;
    }
    NSString *reasonStr =
        reason ? [NSString stringWithUTF8String:reason] : nil;
    OmnixBridgeRegistrationState mapped =
        (OmnixBridgeRegistrationState)state;
    dispatch_async(dispatch_get_main_queue(), ^{
      [bridge handleRegState:mapped sipCode:sip_code reason:reasonStr];
    });
}

static void omnix_bridge_on_call(omnix_call_state_t state,
                                 const omnix_call_info_t *call, void *ctx) {
    OmnixVoiceBridge *bridge = (__bridge OmnixVoiceBridge *)ctx;
    if (!bridge || !call) {
        return;
    }
    OmnixVoiceBridgeCallInfo *info = [[OmnixVoiceBridgeCallInfo alloc]
          initWithCallId:[NSString stringWithUTF8String:call->call_id]
                 peerUri:[NSString stringWithUTF8String:call->peer_uri]
         peerDisplayName:[NSString
                             stringWithUTF8String:call->peer_display_name]
                   state:(OmnixBridgeCallState)state
              isOutgoing:call->is_outgoing ? YES : NO
                 isMuted:call->is_muted ? YES : NO
                isOnHold:call->is_on_hold ? YES : NO];
    dispatch_async(dispatch_get_main_queue(), ^{
      [bridge handleCallEvent:info];
    });
}

static void omnix_bridge_on_error(omnix_error_t err, const char *detail,
                                  void *ctx) {
    OmnixVoiceBridge *bridge = (__bridge OmnixVoiceBridge *)ctx;
    if (!bridge || err == OMNIX_ERR_OK) {
        return;
    }
    OmnixBridgeErrorCode mapped = (OmnixBridgeErrorCode)err;
    if (mapped < OmnixBridgeErrorCodeInitialization ||
        mapped > OmnixBridgeErrorCodeInternal) {
        mapped = OmnixBridgeErrorCodeInternal;
    }
    NSString *detailStr =
        detail ? [NSString stringWithUTF8String:detail] : nil;
    dispatch_async(dispatch_get_main_queue(), ^{
      [bridge handleError:mapped detail:detailStr];
    });
}
