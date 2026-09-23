# SDK-039 — iOS native build entry (invokes ios/build-ios.sh).
# Primary configure/build is cmake -S cpp with vendored ios-cmake toolchain.
# This file exists so Xcode/CI consumers have an ios/ CMake root if needed later.
cmake_minimum_required(VERSION 3.22)
project(omnix_voice_ios_meta LANGUAGES NONE)

message(STATUS "Omnix iOS: use ios/build-ios.sh (macOS) which configures cpp/ with:")
message(STATUS "  -DCMAKE_TOOLCHAIN_FILE=third_party/ios-cmake/ios.toolchain.cmake")
message(STATUS "  -DPLATFORM=OS64|SIMULATORARM64 -DDEPLOYMENT_TARGET=15.0 -DSTATIC=ON")
message(FATAL_ERROR
  "Do not configure ios/CMakeLists.txt directly. Run: ios/build-ios.sh")
