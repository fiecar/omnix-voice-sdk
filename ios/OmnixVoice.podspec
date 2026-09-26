Pod::Spec.new do |s|
  s.name         = "OmnixVoice"
  s.version      = "0.1.0"
  s.summary      = "Omnix Voice iOS source (public Swift API and Objective-C bridge)."
  s.homepage     = "https://github.com/fiecar/omnix-voice-sdk"
  s.license      = "UNLICENSED"
  s.authors      = "Omnix"
  s.platforms    = { :ios => "15.0" }
  s.source       = { :git => "https://github.com/fiecar/omnix-voice-sdk.git", :tag => "v#{s.version}" }
  s.module_name  = "OmnixVoice"
  s.swift_version = "5.0"
  s.static_framework = true

  s.source_files = "Sources/OmnixVoice/**/*.swift", "Sources/OmnixVoiceBridge/**/*.{h,m}"
  s.public_header_files = "Sources/OmnixVoiceBridge/**/*.h"

  s.frameworks = "AVFoundation"

  xcconfig = {
    "DEFINES_MODULE" => "YES",
    "SWIFT_VERSION" => "5.0",
    "CLANG_ENABLE_OBJC_ARC" => "YES",
    "HEADER_SEARCH_PATHS" => "$(inherited) $(PODS_TARGET_SRCROOT)/Sources/OmnixVoiceBridge $(PODS_TARGET_SRCROOT)/../cpp/include",
    "SWIFT_OBJC_BRIDGING_HEADER" => "$(PODS_TARGET_SRCROOT)/Sources/OmnixVoice/OmnixVoice-Bridging-Header.h"
  }

  # Static libraries produced by the iOS CI job. Absent until that job has run.
  sim_libs = File.expand_path("../build/ios-sim", __dir__)
  ssl_libs = File.expand_path("../build/openssl-ios/iphonesimulator-arm64/lib", __dir__)
  if File.directory?(sim_libs) && File.directory?(ssl_libs)
    xcconfig["LIBRARY_SEARCH_PATHS"] = "$(inherited) #{sim_libs} #{ssl_libs}"
    xcconfig["OTHER_LDFLAGS"] = [
      "$(inherited)",
      "-ObjC",
      "-lc++",
      "-lresolv",
      "-force_load #{sim_libs}/libomnix_voice.a",
      "-force_load #{sim_libs}/libbaresip.a",
      "-force_load #{sim_libs}/libre.a",
      "#{ssl_libs}/libssl.a",
      "#{ssl_libs}/libcrypto.a",
      "-framework AVFoundation",
      "-framework AudioToolbox",
      "-framework CoreAudio",
      "-framework Security",
      "-framework CFNetwork",
      "-framework SystemConfiguration",
      "-framework VideoToolbox",
      "-framework Network",
    ].join(" ")
  end
  s.pod_target_xcconfig = xcconfig
end
