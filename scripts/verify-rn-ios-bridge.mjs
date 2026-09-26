/**
 * SDK-049 structural check. Does not compile iOS and does not claim a device.
 * The macOS job compiles the bridge.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const iosDir = path.join(root, 'react-native', 'ios');

function fail(message) {
  console.error(`verify-rn-ios-bridge: ${message}`);
  process.exit(1);
}

function read(name) {
  const file = path.join(iosDir, name);
  if (!fs.existsSync(file)) {
    fail(`missing ${file}`);
  }
  return fs.readFileSync(file, 'utf8');
}

const header = read('OmnixVoiceRN.h');
const source = read('OmnixVoiceRN.mm');
const client = read('OmnixVoiceRNClient.swift');
const combined = header + source + client;

if (!source.includes('RCT_EXPORT_MODULE(OmnixVoiceModule)')) {
  fail('RCT_EXPORT_MODULE(OmnixVoiceModule) missing');
}
if (!source.includes('NativeOmnixVoiceSpec')) {
  fail('module must conform to NativeOmnixVoiceSpec');
}
if (!source.includes('getTurboModule:')) {
  fail('getTurboModule: missing');
}
if (!source.includes('OmnixVoiceRNClient')) {
  fail('bridge must call OmnixVoiceRNClient');
}
if (!client.includes('OmnixVoice.shared')) {
  fail('client must call the public OmnixVoice API');
}

const methods = [
  'initialize:',
  'shutdown:',
  'register:',
  'unregister:',
  'makeCall:',
  'answerCall:',
  'rejectCall:',
  'hangupCall:',
  'holdCall:',
  'resumeCall:',
  'setMuted:',
  'setSpeakerEnabled:',
  'sendDTMF:',
  'transferCall:',
  'getRegistrationState:',
  'addListener:',
  'removeListeners:',
];
for (const method of methods) {
  if (!source.includes(`- (void)${method}`) && !source.includes(`(void)${method}`)) {
    fail(`missing method ${method}`);
  }
}

const events = [
  'omnixRegistrationStateChanged',
  'omnixIncomingCall',
  'omnixCallStateChanged',
  'omnixAudioRouteChanged',
  'omnixError',
];
for (const eventName of events) {
  if (!source.includes(eventName)) {
    fail(`missing event ${eventName}`);
  }
}

if (/baresip\.h|struct\s+ua\b|mem_deref|mem_alloc/i.test(combined)) {
  fail('bridge source leaks a forbidden native type');
}
if (/\bNSLog\b|\bRCTLog\b/.test(source + client)) {
  fail('bridge must not log; configuration can contain a SIP password');
}

console.log('verify-rn-ios-bridge: PASS (source structure, not an iOS compile)');
