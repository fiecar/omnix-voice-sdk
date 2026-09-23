# Omnix Voice Android shared library (SDK-030)
# Produces libomnixvoice.so per ABI; links static libre / libbaresip / OpenSSL
# / omnix_voice from cpp/ (STATIC=ON). JNI bridge arrives in SDK-031.

cmake_minimum_required(VERSION 3.22)
project(omnixvoice_android C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Prefer hidden visibility for all translation units in this tree.
set(CMAKE_C_VISIBILITY_PRESET hidden)
set(CMAKE_CXX_VISIBILITY_PRESET hidden)
set(CMAKE_VISIBILITY_INLINES_HIDDEN ON)
add_compile_options(-fvisibility=hidden)

# Do not pass -Wl,-z,max-page-size=4096 or any page-size override (Issue #2).
# NDK ≥ r28 defaults to 16 KB-compatible ELF alignment.

get_filename_component(OMNIX_ANDROID_DIR "${CMAKE_CURRENT_SOURCE_DIR}" ABSOLUTE)
get_filename_component(OMNIX_REPO_ROOT "${OMNIX_ANDROID_DIR}/.." ABSOLUTE)

# Build static native stack (re, baresip, omnix_voice) from repo cpp/.
add_subdirectory("${OMNIX_REPO_ROOT}/cpp" omnix_cpp_build)

# Shared wrapper: Android anchor + JNI bridge (SDK-031).
add_library(omnixvoice SHARED
  src/main/cpp/omnixvoice_android.c
  src/main/cpp/jni/omnix_jni.cpp
)

target_include_directories(omnixvoice
  PRIVATE
    "${OMNIX_REPO_ROOT}/cpp/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/main/cpp/jni"
)

# Force-link static archives so Baresip module constructors are retained.
# System libs: log (Android), OpenSLES (opensles module), z (compression).
if(ANDROID)
  target_link_libraries(omnixvoice
    PRIVATE
      -Wl,--whole-archive
      omnix_voice
      baresip
      -Wl,--no-whole-archive
      re
      log
      android
      OpenSLES
      z
  )
  if(TARGET OpenSSL::SSL)
    target_link_libraries(omnixvoice PRIVATE OpenSSL::SSL OpenSSL::Crypto)
  endif()
else()
  message(FATAL_ERROR "android/CMakeLists.txt is for ANDROID NDK builds only")
endif()

set_target_properties(omnixvoice PROPERTIES
  OUTPUT_NAME "omnixvoice"
  LIBRARY_OUTPUT_NAME "omnixvoice"
)

# Guard: exactly one shared Omnix library name (allowlist in shipped-native-libs.txt).
message(STATUS "Omnix Android: building libomnixvoice.so for ABI=${ANDROID_ABI}")
