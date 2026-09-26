#!/usr/bin/env bash
# SDK-049 — compile the iOS React Native bridge on macOS.
# Uses the public Swift OmnixVoice API. Does not build an XCFramework.
# Does not place a SIP call. Physical iPhone is not used.
set -euo pipefail

fail() { echo "build-ios-rn-bridge: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ "$(uname -s)" == "Darwin" ]] || fail "must run on macOS"

[[ -f "$ROOT/build/ios-sim/libomnix_voice.a" ]] || fail "missing build/ios-sim/libomnix_voice.a"
[[ -f "$ROOT/build/ios-sim/libbaresip.a" ]] || fail "missing build/ios-sim/libbaresip.a"
[[ -f "$ROOT/build/ios-sim/libre.a" ]] || fail "missing build/ios-sim/libre.a"
[[ -f "$ROOT/build/openssl-ios/iphonesimulator-arm64/lib/libssl.a" ]] || fail "missing iOS simulator libssl.a"
[[ -d "$ROOT/react-native/node_modules/react-native" ]] || fail "run npm ci in react-native first"

node "$ROOT/scripts/verify-rn-ios-bridge.mjs"

WORK="$ROOT/build/ios-rn-host"
rm -rf "$WORK"
mkdir -p "$WORK"

cat > "$WORK/main.m" <<'EOF'
#import <UIKit/UIKit.h>

int main(int argc, char *argv[])
{
  @autoreleasepool {
    return UIApplicationMain(argc, argv, nil, nil);
  }
}
EOF

cat > "$WORK/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
  <key>CFBundleExecutable</key>
  <string>$(EXECUTABLE_NAME)</string>
  <key>CFBundleName</key>
  <string>$(PRODUCT_NAME)</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSRequiresIPhoneOS</key>
  <true/>
</dict>
</plist>
EOF

cat > "$WORK/Podfile" <<EOF
require_relative '${ROOT}/react-native/node_modules/react-native/scripts/react_native_pods'

platform :ios, min_ios_version_supported
prepare_react_native_project!

target 'OmnixRNCompile' do
  use_react_native!(
    :path => '${ROOT}/react-native/node_modules/react-native',
    :app_path => '${ROOT}/react-native'
  )
  pod 'OmnixVoice', :path => '${ROOT}/ios'
  pod 'omnix-voice-sdk', :path => '${ROOT}/react-native'
end

post_install do |installer|
  react_native_post_install(
    installer,
    '${ROOT}/react-native/node_modules/react-native',
    :mac_catalyst_enabled => false
  )
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
      config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
    end
  end
end
EOF

ruby - "$WORK" <<'RUBY'
require 'xcodeproj'
work = ARGV.fetch(0)
project_path = File.join(work, 'OmnixRNCompile.xcodeproj')
project = Xcodeproj::Project.new(project_path)
target = project.new_target(:application, 'OmnixRNCompile', :ios, '15.1')
ref = project.main_group.new_file('main.m')
target.source_build_phase.add_file_reference(ref)
target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.omnix.voice.rncompile'
  config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
  config.build_settings['INFOPLIST_FILE'] = 'Info.plist'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.1'
  config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  config.build_settings['SUPPORTED_PLATFORMS'] = 'iphonesimulator'
  config.build_settings['SDKROOT'] = 'iphonesimulator'
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.set_launch_target(target)
scheme.save_as(project.path, 'OmnixRNCompile', true)
RUBY

cd "$WORK"
pod install
xcodebuild \
  -workspace "$WORK/OmnixRNCompile.xcworkspace" \
  -scheme OmnixRNCompile \
  -sdk iphonesimulator \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "build-ios-rn-bridge: SUCCESS"
