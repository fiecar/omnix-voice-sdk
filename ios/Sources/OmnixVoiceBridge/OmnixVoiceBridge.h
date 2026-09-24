/**
 * Omnix Voice — Objective-C bridge (SDK-040).
 *
 * Intermediate layer between the public C facade and the Swift facade
 * (SDK-041). This header exposes Omnix ObjC types only.
 *
 * MUST NOT include baresip.h, re.h, or any Baresip/re type.
 * Placeholders only; no credentials or secrets.
 */
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class OmnixVoiceBridge;
@class OmnixVoiceBridgeConfig;
@class OmnixVoiceBridgeCallInfo;

/** Maps omnix_reg_state_t ordinals (Issue #1 §20A.3). */
typedef NS_ENUM(NSInteger, OmnixBridgeRegistrationState) {
    OmnixBridgeRegistrationStateUninitialized = 0,
    OmnixBridgeRegistrationStateUnregistered = 1,
    OmnixBridgeRegistrationStateRegistering = 2,
    OmnixBridgeRegistrationStateRegistered = 3,
    OmnixBridgeRegistrationStateFailed = 4,
};

/** Maps omnix_call_state_t ordinals (Issue #1 §20A.4). */
typedef NS_ENUM(NSInteger, OmnixBridgeCallState) {
    OmnixBridgeCallStateIdle = 0,
    OmnixBridgeCallStateOutgoing = 1,
    OmnixBridgeCallStateIncoming = 2,
    OmnixBridgeCallStateRinging = 3,
    OmnixBridgeCallStateEarlyMedia = 4,
    OmnixBridgeCallStateConnected = 5,
    OmnixBridgeCallStateHeld = 6,
    OmnixBridgeCallStateEnding = 7,
    OmnixBridgeCallStateEnded = 8,
    OmnixBridgeCallStateFailed = 9,
};

/**
 * Maps omnix_error_t (non-OK). OMNIX_ERR_OK never surfaces.
 * Ordinals match Issue #1 §20A.6 (1 = INITIALIZATION … 17 = INTERNAL).
 */
typedef NS_ENUM(NSInteger, OmnixBridgeErrorCode) {
    OmnixBridgeErrorCodeInitialization = 1,
    OmnixBridgeErrorCodeInvalidConfiguration = 2,
    OmnixBridgeErrorCodeRegistrationFailed = 3,
    OmnixBridgeErrorCodeAuthenticationFailed = 4,
    OmnixBridgeErrorCodeNetworkUnavailable = 5,
    OmnixBridgeErrorCodeTls = 6,
    OmnixBridgeErrorCodeMedia = 7,
    OmnixBridgeErrorCodeCallFailed = 8,
    OmnixBridgeErrorCodeCallBusy = 9,
    OmnixBridgeErrorCodeCallRejected = 10,
    OmnixBridgeErrorCodeTimeout = 11,
    OmnixBridgeErrorCodeNotRegistered = 12,
    OmnixBridgeErrorCodeInvalidCallState = 13,
    OmnixBridgeErrorCodePermissionDenied = 14,
    OmnixBridgeErrorCodeTransferFailed = 15,
    OmnixBridgeErrorCodeNotSupported = 16,
    OmnixBridgeErrorCodeInternal = 17,
};

FOUNDATION_EXPORT NSErrorDomain const OmnixVoiceBridgeErrorDomain;

@interface OmnixVoiceBridgeConfig : NSObject

@property (nonatomic, copy) NSString *sipServer;
@property (nonatomic, copy) NSString *sipUser;
@property (nonatomic, copy) NSString *sipPassword;
@property (nonatomic, copy, nullable) NSString *authUser;
@property (nonatomic, copy, nullable) NSString *displayName;
@property (nonatomic, copy, nullable) NSString *stunServer;
@property (nonatomic, assign) BOOL verifyCert;   /* default YES */
@property (nonatomic, assign) BOOL enableSrtp;   /* default YES */
/** Comma-separated preference; default nil → C facade default. */
@property (nonatomic, copy, nullable) NSString *codecs;

/**
 * Redacts sipPassword. Never log the raw password.
 */
- (NSString *)description;

@end

@interface OmnixVoiceBridgeCallInfo : NSObject

@property (nonatomic, copy, readonly) NSString *callId;
@property (nonatomic, copy, readonly) NSString *peerUri;
@property (nonatomic, copy, readonly) NSString *peerDisplayName;
@property (nonatomic, assign, readonly) OmnixBridgeCallState state;
@property (nonatomic, assign, readonly) BOOL isOutgoing;
@property (nonatomic, assign, readonly) BOOL isMuted;
@property (nonatomic, assign, readonly) BOOL isOnHold;

- (instancetype)initWithCallId:(NSString *)callId
                       peerUri:(NSString *)peerUri
               peerDisplayName:(NSString *)peerDisplayName
                         state:(OmnixBridgeCallState)state
                    isOutgoing:(BOOL)isOutgoing
                       isMuted:(BOOL)isMuted
                      isOnHold:(BOOL)isOnHold;

@end

@protocol OmnixVoiceBridgeDelegate <NSObject>
@optional
- (void)omnixVoiceBridge:(OmnixVoiceBridge *)bridge
    registrationStateChanged:(OmnixBridgeRegistrationState)state
                     sipCode:(NSInteger)sipCode
                      reason:(nullable NSString *)reason;

- (void)omnixVoiceBridge:(OmnixVoiceBridge *)bridge
            incomingCall:(OmnixVoiceBridgeCallInfo *)call;

- (void)omnixVoiceBridge:(OmnixVoiceBridge *)bridge
        callStateChanged:(OmnixVoiceBridgeCallInfo *)call;

- (void)omnixVoiceBridge:(OmnixVoiceBridge *)bridge
                   error:(OmnixBridgeErrorCode)code
                  detail:(nullable NSString *)detail;
@end

/**
 * Objective-C bridge singleton wrapping the Omnix C facade.
 * All C callbacks are forwarded to [delegate] on the main queue.
 */
@interface OmnixVoiceBridge : NSObject

@property (class, nonatomic, readonly) OmnixVoiceBridge *sharedBridge;

@property (nonatomic, weak, nullable) id<OmnixVoiceBridgeDelegate> delegate;

@property (nonatomic, assign, readonly) OmnixBridgeRegistrationState registrationState;
@property (nonatomic, assign, readonly, getter=isInitialized) BOOL initialized;

/**
 * Initialize the native facade. Copies config string values into Omnix-owned
 * storage via omnix_init — never writes into caller-owned password memory.
 * @return YES on success; on failure fills error (OmnixVoiceBridgeErrorDomain).
 */
- (BOOL)initializeWithConfig:(OmnixVoiceBridgeConfig *)config
                       error:(NSError *_Nullable *_Nullable)error;

- (void)shutdown;

- (BOOL)registerWithError:(NSError *_Nullable *_Nullable)error;
- (void)unregister;

/**
 * @param callIdOut On success, receives a non-empty call id (caller-owned).
 */
- (BOOL)makeCall:(NSString *)destination
          callId:(NSString *_Nullable *_Nullable)callIdOut
           error:(NSError *_Nullable *_Nullable)error;

- (BOOL)answerCall:(NSString *)callId error:(NSError *_Nullable *_Nullable)error;
- (BOOL)rejectCall:(NSString *)callId error:(NSError *_Nullable *_Nullable)error;
- (BOOL)hangupCall:(NSString *)callId error:(NSError *_Nullable *_Nullable)error;
- (BOOL)holdCall:(NSString *)callId error:(NSError *_Nullable *_Nullable)error;
- (BOOL)resumeCall:(NSString *)callId error:(NSError *_Nullable *_Nullable)error;
- (BOOL)setMuted:(BOOL)muted
          callId:(NSString *)callId
           error:(NSError *_Nullable *_Nullable)error;
- (BOOL)setSpeakerEnabled:(BOOL)enabled
                    error:(NSError *_Nullable *_Nullable)error;
- (BOOL)sendDTMF:(unichar)digit
          callId:(NSString *)callId
           error:(NSError *_Nullable *_Nullable)error;

/** Blind transfer via C facade (may return NOT_SUPPORTED until SDK-024). */
- (BOOL)transferCall:(NSString *)callId
         destination:(NSString *)destination
               error:(NSError *_Nullable *_Nullable)error;

- (nullable OmnixVoiceBridgeCallInfo *)callInfoForCallId:(NSString *)callId;

@end

NS_ASSUME_NONNULL_END
