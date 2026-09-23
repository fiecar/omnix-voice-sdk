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

# SDK-038: Do NOT pass -Wl,-z,max-page-size=4096 (that reverts to 4 KB and breaks 16 KB compat).
# NDK ≥ r28 sets PT_LOAD alignment to 0x4000 via its ELF linker script, but GNU_RELRO end
# alignment still requires explicit -Wl,-z,max-page-size=16384 (see target_link_options below).

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

  # SDK-038: Explicit 16 KB page-size enforcement (lead-approved defensive build invariant).
  #
  # NDK r28+ sets PT_LOAD alignment to 0x4000 via the ELF linker script.  However,
  # LLD's GNU_RELRO end is rounded up using max-page-size, which defaults to 4096 in
  # the android.toolchain.cmake (non-legacy) path — so without explicit flags the
  # RELRO segment end is NOT 16 KB aligned and the SDK-038 validator fails.
  #
  # -Wl,-z,max-page-size=16384  — pads the GNU_RELRO end to a 16 KB boundary.
  # -Wl,-z,common-page-size=16384 — aligns common-section allocations to 16 KB.
  #
  # These flags are Android-only, target-specific, and do NOT affect host or iOS builds.
  # See: https://developer.android.com/guide/practices/page-sizes
  # See: docs/toolchain.md §16 KB defensive build invariant
  target_link_options(omnixvoice
    PRIVATE
      "-Wl,-z,max-page-size=16384"
      "-Wl,-z,common-page-size=16384"
  )
else()
  message(FATAL_ERROR "android/CMakeLists.txt is for ANDROID NDK builds only")
endif()

set_target_properties(omnixvoice PROPERTIES
  OUTPUT_NAME "omnixvoice"
  LIBRARY_OUTPUT_NAME "omnixvoice"
)

# Guard: exactly one shared Omnix library name (allowlist in shipped-native-libs.txt).
message(STATUS "Omnix Android: building libomnixvoice.so for ABI=${ANDROID_ABI}")
