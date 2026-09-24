require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "omnix-voice-sdk"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = "Omnix"
  s.platforms    = { :ios => "15.0" }
  s.source       = { :git => "https://github.com/fiecar/omnix-voice-sdk.git", :tag => "v#{s.version}" }

  s.source_files = "ios/**/*.{h,m,mm,swift}"
  s.exclude_files = "ios/**/Tests/**"

  # XCFramework produced by SDK-043 (may be absent until that task unblocks).
  # pack-rn copies dist/OmnixVoiceSDK.xcframework here when available.
  xcframework_path = "ios/OmnixVoiceSDK.xcframework"
  if File.exist?(File.join(__dir__, xcframework_path))
    s.vendored_frameworks = xcframework_path
  end

  s.pod_target_xcconfig = {
    "DEFINES_MODULE" => "YES",
    "SWIFT_VERSION" => "5.0",
    "OTHER_CPLUSPLUSFLAGS" => "$(inherited) -DRCT_NEW_ARCH_ENABLED=1"
  }

  install_modules_dependencies(s)
end
