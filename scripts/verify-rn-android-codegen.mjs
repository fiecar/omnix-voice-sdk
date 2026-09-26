/**
 * SDK-048: regenerate the RN 0.87 Android TurboModule spec and check the
 * Kotlin bridge implements it. Does not claim a device or SIP call.
 */
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const rnDir = path.join(root, 'react-native');
const modulePath = path.join(
  rnDir,
  'android',
  'src',
  'main',
  'java',
  'com',
  'omnix',
  'voice',
  'rn',
  'OmnixVoiceModule.kt',
);
const packagePath = path.join(
  rnDir,
  'android',
  'src',
  'main',
  'java',
  'com',
  'omnix',
  'voice',
  'rn',
  'OmnixVoicePackage.kt',
);
const eventsPath = path.join(rnDir, 'src', 'events.ts');

function fail(message) {
  console.error(`verify-rn-android-codegen: ${message}`);
  process.exit(1);
}

const out = fs.mkdtempSync(path.join(os.tmpdir(), 'omnix-rn-codegen-'));
const schemaPath = path.join(out, 'schema.json');
const androidOut = path.join(out, 'android');

execFileSync(
  process.execPath,
  [
    path.join(
      rnDir,
      'node_modules',
      '@react-native',
      'codegen',
      'lib',
      'cli',
      'combine',
      'combine-js-to-schema-cli.js',
    ),
    schemaPath,
    path.join(rnDir, 'src', 'NativeOmnixVoice.ts'),
    '--libraryName',
    'OmnixVoiceSpec',
  ],
  { stdio: 'inherit' },
);

execFileSync(
  process.execPath,
  [
    path.join(rnDir, 'node_modules', 'react-native', 'scripts', 'generate-specs-cli.js'),
    '--platform',
    'android',
    '--schemaPath',
    schemaPath,
    '--outputDir',
    androidOut,
    '--libraryName',
    'OmnixVoiceSpec',
    '--javaPackageName',
    'com.omnix.voice.rn',
    '--libraryType',
    'modules',
  ],
  { stdio: 'inherit' },
);

const specPath = path.join(
  androidOut,
  'java',
  'com',
  'omnix',
  'voice',
  'rn',
  'NativeOmnixVoiceSpec.java',
);
if (!fs.existsSync(specPath)) {
  fail(`missing generated spec at ${specPath}`);
}

const spec = fs.readFileSync(specPath, 'utf8');
if (!spec.includes('NAME = "OmnixVoiceModule"')) {
  fail('generated spec module name is not OmnixVoiceModule');
}

const methods = [...spec.matchAll(/public abstract void (\w+)\(/g)].map((match) => match[1]);
if (methods.length < 16) {
  fail(`expected the frozen method set, found ${methods.join(', ')}`);
}

const moduleSource = fs.readFileSync(modulePath, 'utf8');
const packageSource = fs.readFileSync(packagePath, 'utf8');
for (const name of methods) {
  if (!moduleSource.includes(`override fun ${name}(`)) {
    fail(`OmnixVoiceModule.kt does not override ${name}`);
  }
}

const eventNames = [
  'omnixRegistrationStateChanged',
  'omnixIncomingCall',
  'omnixCallStateChanged',
  'omnixAudioRouteChanged',
  'omnixError',
];
const eventsSource = fs.readFileSync(eventsPath, 'utf8');
for (const eventName of eventNames) {
  if (!eventsSource.includes(eventName) || !moduleSource.includes(eventName)) {
    fail(`event name missing from TS or Kotlin: ${eventName}`);
  }
}

if (!packageSource.includes('BaseReactPackage')) {
  fail('OmnixVoicePackage must extend BaseReactPackage');
}
if (!packageSource.includes('ReactModuleInfo(') || !/,\s*true,\s*\)/.test(packageSource)) {
  fail('OmnixVoicePackage must register the module as a TurboModule');
}
if (/\bLog\./.test(moduleSource)) {
  fail('bridge must not log; configuration can contain a SIP password');
}
if (/baresip|struct\s+ua\b|\bre\.h\b|\bjni\b/i.test(moduleSource + packageSource)) {
  fail('bridge source leaks a forbidden native type');
}

console.log(`verify-rn-android-codegen: PASS (${methods.length} methods, module OmnixVoiceModule)`);
