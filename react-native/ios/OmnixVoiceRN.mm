#import "OmnixVoiceRN.h"

#import <OmnixVoiceSpec/OmnixVoiceSpec.h>
#import "OmnixVoiceSDK-Swift.h"

@interface OmnixVoiceRN () <NativeOmnixVoiceSpec, OmnixVoiceRNEventSink>
@end

@implementation OmnixVoiceRN

RCT_EXPORT_MODULE(OmnixVoiceModule)

+ (BOOL)requiresMainQueueSetup
{
  return NO;
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeOmnixVoiceSpecJSI>(params);
}

- (NSArray<NSString *> *)supportedEvents
{
  return @[
    @"omnixRegistrationStateChanged",
    @"omnixIncomingCall",
    @"omnixCallStateChanged",
    @"omnixAudioRouteChanged",
    @"omnixError",
  ];
}

- (void)initialize:(JS::NativeOmnixVoice::OmnixNativeConfig &)config
           resolve:(RCTPromiseResolveBlock)resolve
            reject:(RCTPromiseRejectBlock)reject
{
  NSString *secret = config.sipPassword() ?: @"";
  OmnixVoiceRNClient *client = OmnixVoiceRNClient.shared;
  client.eventSink = self;
  NSString *code = nil;
  NSString *detail = nil;
  BOOL verifyCert = config.verifyCert().has_value() ? config.verifyCert().value() : YES;
  BOOL enableSrtp = config.enableSrtp().has_value() ? config.enableSrtp().value() : YES;
  BOOL ok = [client initializeWithSipServer:config.sipServer() ?: @""
                                    sipUser:config.sipUser() ?: @""
                                sipPassword:secret
                                   authUser:config.authUser()
                                displayName:config.displayName()
                                 stunServer:config.stunServer()
                                 verifyCert:verifyCert
                                 enableSrtp:enableSrtp
                                     codecs:config.codecs()
                                  errorCode:&code
                               errorDetail:&detail];
  if (ok) {
    resolve(nil);
    return;
  }
  if (code == nil || ![code isEqualToString:@"INVALID_CALL_STATE"]) {
    client.eventSink = nil;
  }
  [self reject:reject code:code detail:detail secret:secret];
}

- (void)shutdown:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  OmnixVoiceRNClient *client = OmnixVoiceRNClient.shared;
  client.eventSink = nil;
  [client shutdownClient];
  resolve(nil);
}

- (void)register:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  [self run:resolve reject:reject body:^BOOL(NSString **code, NSString **detail) {
    return [OmnixVoiceRNClient.shared registerAccountWithErrorCode:code errorDetail:detail];
  }];
}

- (void)unregister:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  [OmnixVoiceRNClient.shared unregisterAccount];
  resolve(nil);
}

- (void)makeCall:(NSString *)destination
         resolve:(RCTPromiseResolveBlock)resolve
          reject:(RCTPromiseRejectBlock)reject
{
  NSString *code = nil;
  NSString *detail = nil;
  NSString *callId = [OmnixVoiceRNClient.shared makeCall:destination errorCode:&code errorDetail:&detail];
  if (callId != nil) {
    resolve(callId);
    return;
  }
  [self reject:reject code:code detail:detail secret:nil];
}

- (void)answerCall:(NSString *)callId
           resolve:(RCTPromiseResolveBlock)resolve
            reject:(RCTPromiseRejectBlock)reject
{
  [self run:resolve reject:reject body:^BOOL(NSString **code, NSString **detail) {
    return [OmnixVoiceRNClient.shared answerCall:callId errorCode:code errorDetail:detail];
  }];
}

- (void)rejectCall:(NSString *)callId
           resolve:(RCTPromiseResolveBlock)resolve
            reject:(RCTPromiseRejectBlock)reject
{
  [self run:resolve reject:reject body:^BOOL(NSString **code, NSString **detail) {
    return [OmnixVoiceRNClient.shared rejectCall:callId errorCode:code errorDetail:detail];
  }];
}

- (void)hangupCall:(NSString *)callId
           resolve:(RCTPromiseResolveBlock)resolve
            reject:(RCTPromiseRejectBlock)reject
{
  [self run:resolve reject:reject body:^BOOL(NSString **code, NSString **detail) {
    return [OmnixVoiceRNClient.shared hangupCall:callId errorCode:code errorDetail:detail];
  }];
}

- (void)holdCall:(NSString *)callId
         resolve:(RCTPromiseResolveBlock)resolve
          reject:(RCTPromiseRejectBlock)reject
{
  [self run:resolve reject:reject body:^BOOL(NSString **code, NSString **detail) {
    return [OmnixVoiceRNClient.shared holdCall:callId errorCode:code errorDetail:detail];
  }];
}

- (void)resumeCall:(NSString *)callId
           resolve:(RCTPromiseResolveBlock)resolve
            reject:(RCTPromiseRejectBlock)reject
{
  [self run:resolve reject:reject body:^BOOL(NSString **code, NSString **detail) {
    return [OmnixVoiceRNClient.shared resumeCall:callId errorCode:code errorDetail:detail];
  }];
}

- (void)setMuted:(NSString *)callId
           muted:(BOOL)muted
         resolve:(RCTPromiseResolveBlock)resolve
          reject:(RCTPromiseRejectBlock)reject
{
  [self run:resolve reject:reject body:^BOOL(NSString **code, NSString **detail) {
    return [OmnixVoiceRNClient.shared setMuted:muted callId:callId errorCode:code errorDetail:detail];
  }];
}

- (void)setSpeakerEnabled:(BOOL)enabled
                  resolve:(RCTPromiseResolveBlock)resolve
                   reject:(RCTPromiseRejectBlock)reject
{
  [self run:resolve reject:reject body:^BOOL(NSString **code, NSString **detail) {
    return [OmnixVoiceRNClient.shared setSpeakerEnabled:enabled errorCode:code errorDetail:detail];
  }];
}

- (void)sendDTMF:(NSString *)callId
           digit:(NSString *)digit
         resolve:(RCTPromiseResolveBlock)resolve
          reject:(RCTPromiseRejectBlock)reject
{
  [self run:resolve reject:reject body:^BOOL(NSString **code, NSString **detail) {
    return [OmnixVoiceRNClient.shared sendDTMF:callId digit:digit errorCode:code errorDetail:detail];
  }];
}

- (void)transferCall:(NSString *)callId
         destination:(NSString *)destination
             resolve:(RCTPromiseResolveBlock)resolve
              reject:(RCTPromiseRejectBlock)reject
{
  [self run:resolve reject:reject body:^BOOL(NSString **code, NSString **detail) {
    return [OmnixVoiceRNClient.shared transferCall:callId destination:destination errorCode:code errorDetail:detail];
  }];
}

- (void)getRegistrationState:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  resolve([OmnixVoiceRNClient.shared currentRegistrationState]);
}

- (void)addListener:(NSString *)eventName
{
}

- (void)removeListeners:(double)count
{
}

- (void)rnRegistrationStateChanged:(NSString *)state
                           sipCode:(NSNumber *)sipCode
                            reason:(NSString *)reason
{
  NSMutableDictionary *payload = [NSMutableDictionary dictionary];
  payload[@"state"] = state ?: @"";
  if (sipCode != nil) {
    payload[@"sipCode"] = sipCode;
  }
  if (reason.length > 0) {
    payload[@"reason"] = reason;
  }
  [self emit:@"omnixRegistrationStateChanged" body:payload];
}

- (void)rnIncomingCall:(NSDictionary *)call
{
  [self emit:@"omnixIncomingCall" body:call];
}

- (void)rnCallStateChanged:(NSDictionary *)call
{
  [self emit:@"omnixCallStateChanged" body:call];
}

- (void)rnAudioRouteChanged:(NSString *)route
{
  [self emit:@"omnixAudioRouteChanged" body:@{@"route" : route ?: @"UNKNOWN"}];
}

- (void)rnError:(NSString *)code detail:(NSString *)detail callId:(NSString *)callId
{
  NSMutableDictionary *payload = [NSMutableDictionary dictionary];
  payload[@"code"] = code ?: @"INTERNAL_NATIVE_ERROR";
  if (detail.length > 0) {
    payload[@"detail"] = detail;
  }
  if (callId.length > 0) {
    payload[@"callId"] = callId;
  }
  [self emit:@"omnixError" body:payload];
}

- (void)emit:(NSString *)name body:(id)body
{
  if (self.bridge == nil) {
    return;
  }
  [self sendEventWithName:name body:body];
}

- (void)run:(RCTPromiseResolveBlock)resolve
     reject:(RCTPromiseRejectBlock)reject
       body:(BOOL (^)(NSString **code, NSString **detail))body
{
  NSString *code = nil;
  NSString *detail = nil;
  if (body(&code, &detail)) {
    resolve(nil);
    return;
  }
  [self reject:reject code:code detail:detail secret:nil];
}

- (void)reject:(RCTPromiseRejectBlock)reject
          code:(NSString *)code
        detail:(NSString *)detail
        secret:(NSString *)secret
{
  NSString *safeCode = code.length > 0 ? code : @"INTERNAL_NATIVE_ERROR";
  NSString *safeDetail = [self scrub:detail secret:secret];
  if (safeDetail.length == 0) {
    safeDetail = safeCode;
  }
  reject(safeCode, safeDetail, nil);
}

- (NSString *)scrub:(NSString *)detail secret:(NSString *)secret
{
  if (detail.length == 0) {
    return @"";
  }
  NSString *out = detail;
  if (secret.length > 0 && [out containsString:secret]) {
    out = [out stringByReplacingOccurrencesOfString:secret withString:@"[REDACTED]"];
  }
  NSRegularExpression *regex = [NSRegularExpression
      regularExpressionWithPattern:@"(?i)((?:sipPassword|auth_pass|password)\\s*[:=]\\s*)(\\S+)"
                           options:0
                             error:nil];
  if (regex != nil) {
    out = [regex stringByReplacingMatchesInString:out
                                          options:0
                                            range:NSMakeRange(0, out.length)
                                     withTemplate:@"$1[REDACTED]"];
  }
  if (out.length > 180) {
    out = [out substringToIndex:180];
  }
  return out;
}

@end
