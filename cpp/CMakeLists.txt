# Omnix Voice native build foundation (SDK-009)
# Builds static libre.a + libbaresip.a from third_party/ and a stub libomnix_voice.a.
# Android/iOS MUST use the pinned OpenSSL from SDK-066 (never system OpenSSL).

cmake_minimum_required(VERSION 3.22)
project(omnix_voice_native C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# -----------------------------------------------------------------------------
# Paths
# -----------------------------------------------------------------------------
get_filename_component(OMNIX_REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)
set(OMNIX_RE_SRC "${OMNIX_REPO_ROOT}/third_party/re")
set(OMNIX_BARESIP_SRC "${OMNIX_REPO_ROOT}/third_party/baresip")

if(NOT EXISTS "${OMNIX_RE_SRC}/CMakeLists.txt")
  message(FATAL_ERROR "Missing vendored re at ${OMNIX_RE_SRC}")
endif()
if(NOT EXISTS "${OMNIX_BARESIP_SRC}/CMakeLists.txt")
  message(FATAL_ERROR "Missing vendored baresip at ${OMNIX_BARESIP_SRC}")
endif()

# -----------------------------------------------------------------------------
# Static-only (Issue #2 SDK-009)
# -----------------------------------------------------------------------------
set(STATIC ON CACHE BOOL "Build baresip static" FORCE)
set(LIBRE_BUILD_SHARED OFF CACHE BOOL "Do not build shared libre" FORCE)
set(LIBRE_BUILD_STATIC ON CACHE BOOL "Build static libre" FORCE)

# -----------------------------------------------------------------------------
# OpenSSL (SDK-066 pinned snapshot / static build)
# Pass -DOMNIX_OPENSSL_ROOT=<prefix> where prefix contains include/ and lib/.
# For Android ABIs: build/openssl-android/<abi> from fetch-openssl-android.ps1
# or scripts/build-openssl-android.sh.
# -----------------------------------------------------------------------------
if(NOT OMNIX_OPENSSL_ROOT AND DEFINED ENV{OMNIX_OPENSSL_ROOT})
  set(OMNIX_OPENSSL_ROOT "$ENV{OMNIX_OPENSSL_ROOT}")
endif()

if(ANDROID)
  if(NOT OMNIX_OPENSSL_ROOT)
    set(_omnix_abi "${ANDROID_ABI}")
    if(NOT _omnix_abi)
      set(_omnix_abi "${CMAKE_ANDROID_ARCH_ABI}")
    endif()
    set(_omnix_guess "${OMNIX_REPO_ROOT}/build/openssl-android/${_omnix_abi}")
    if(EXISTS "${_omnix_guess}/lib/libssl.a" AND EXISTS "${_omnix_guess}/lib/libcrypto.a")
      set(OMNIX_OPENSSL_ROOT "${_omnix_guess}")
    endif()
  endif()
  if(NOT OMNIX_OPENSSL_ROOT)
    message(FATAL_ERROR
      "Android builds require pinned OpenSSL (SDK-066). "
      "Set OMNIX_OPENSSL_ROOT to build/openssl-android/<abi> "
      "(run scripts/fetch-openssl-android.ps1 or build-openssl-android.sh).")
  endif()
endif()

if(OMNIX_OPENSSL_ROOT)
  get_filename_component(OMNIX_OPENSSL_ROOT "${OMNIX_OPENSSL_ROOT}" ABSOLUTE)
  if(NOT EXISTS "${OMNIX_OPENSSL_ROOT}/include/openssl/ssl.h")
    message(FATAL_ERROR "OMNIX_OPENSSL_ROOT missing include/openssl/ssl.h: ${OMNIX_OPENSSL_ROOT}")
  endif()
  if(NOT EXISTS "${OMNIX_OPENSSL_ROOT}/lib/libssl.a" OR NOT EXISTS "${OMNIX_OPENSSL_ROOT}/lib/libcrypto.a")
    message(FATAL_ERROR "OMNIX_OPENSSL_ROOT missing static libssl.a/libcrypto.a: ${OMNIX_OPENSSL_ROOT}")
  endif()

  # FindOpenSSL is unreliable for Android NDK cross-builds (host=Windows,
  # target=.a archives). Wire imported targets from the SDK-066 prefix.
  set(OPENSSL_ROOT_DIR "${OMNIX_OPENSSL_ROOT}" CACHE PATH "Pinned OpenSSL prefix" FORCE)
  set(OPENSSL_USE_STATIC_LIBS TRUE CACHE BOOL "" FORCE)
  set(OPENSSL_INCLUDE_DIR "${OMNIX_OPENSSL_ROOT}/include" CACHE PATH "" FORCE)
  set(OPENSSL_CRYPTO_LIBRARY "${OMNIX_OPENSSL_ROOT}/lib/libcrypto.a" CACHE FILEPATH "" FORCE)
  set(OPENSSL_SSL_LIBRARY "${OMNIX_OPENSSL_ROOT}/lib/libssl.a" CACHE FILEPATH "" FORCE)
  set(OPENSSL_LIBRARIES "${OPENSSL_SSL_LIBRARY};${OPENSSL_CRYPTO_LIBRARY}" CACHE STRING "" FORCE)
  set(OPENSSL_VERSION "3.5.8" CACHE STRING "" FORCE)
  set(OPENSSL_FOUND TRUE CACHE BOOL "" FORCE)

  if(NOT TARGET OpenSSL::Crypto)
    add_library(OpenSSL::Crypto STATIC IMPORTED GLOBAL)
    set_target_properties(OpenSSL::Crypto PROPERTIES
      IMPORTED_LOCATION "${OPENSSL_CRYPTO_LIBRARY}"
      INTERFACE_INCLUDE_DIRECTORIES "${OPENSSL_INCLUDE_DIR}")
  endif()
  if(NOT TARGET OpenSSL::SSL)
    add_library(OpenSSL::SSL STATIC IMPORTED GLOBAL)
    set_target_properties(OpenSSL::SSL PROPERTIES
      IMPORTED_LOCATION "${OPENSSL_SSL_LIBRARY}"
      INTERFACE_INCLUDE_DIRECTORIES "${OPENSSL_INCLUDE_DIR}"
      INTERFACE_LINK_LIBRARIES OpenSSL::Crypto)
  endif()
  message(STATUS "Omnix: using pinned OpenSSL at ${OMNIX_OPENSSL_ROOT}")
else()
  find_package(OpenSSL 1.1.1)
  if(NOT OPENSSL_FOUND)
    message(WARNING
      "OpenSSL not found. Host builds need OpenSSL (prefer building from "
      "third_party/openssl). Android/iOS MUST set OMNIX_OPENSSL_ROOT.")
  endif()
endif()

# -----------------------------------------------------------------------------
# re (libre)
# -----------------------------------------------------------------------------
add_subdirectory("${OMNIX_RE_SRC}" "${CMAKE_CURRENT_BINARY_DIR}/re_build")

# Satisfy baresip's FindRE.cmake without installing re first.
# Linking uses the CMake target name "re" created above.
set(RE_INCLUDE_DIR "${OMNIX_RE_SRC}/include" CACHE PATH "re include dir" FORCE)
set(RE_LIBRARY re CACHE FILEPATH "re CMake target" FORCE)
set(RE_INCLUDE_DIRS "${RE_INCLUDE_DIR}")
set(RE_LIBRARIES re)
set(RE_FOUND TRUE)

# Point baresip's find_package(re CONFIG) at vendored re-config.cmake
# (HINTS ../re/cmake is unreliable under add_subdirectory).
set(re_DIR "${OMNIX_RE_SRC}/cmake" CACHE PATH "Directory containing re-config.cmake" FORCE)

# Curated module set for Omnix MVP embedding (Android/iOS).
# Excludes desktop-only modules whose Find*.cmake call
# find_package(PkgConfig REQUIRED) (e.g. v4l2) which breaks NDK
# cross-configure on Windows hosts. Opus lands in SDK-067.
# aaudio is deferred: upstream module uses API-28-only AAudio symbols
# while Omnix Android minSdk is 26 (opensles covers MVP audio).
set(OMNIX_BARESIP_MODULES
  account
  aubridge
  auconv
  aufile
  augain
  auresamp
  ausine
  contact
  ctrl_tcp
  debug_cmd
  dtls_srtp
  echo
  fakevideo
  g711
  httpreq
  ice
  in_band_dtmf
  l16
  menu
  mixausrc
  mixminus
  mwi
  natpmp
  netroam
  opensles
  presence
  rtcpsummary
  selfview
  serreg
  srtp
  stdio
  stun
  turn
  uuid
  vidbridge
  vidinfo
  vumeter
)
set(MODULES "${OMNIX_BARESIP_MODULES}" CACHE STRING "Baresip modules for Omnix" FORCE)

# SDK-026: dtls_srtp (+ srtp) must remain in the static module list.
list(FIND OMNIX_BARESIP_MODULES "dtls_srtp" _omnix_mod_dtls_srtp)
if(_omnix_mod_dtls_srtp EQUAL -1)
  message(FATAL_ERROR "SDK-026: OMNIX_BARESIP_MODULES must include dtls_srtp")
endif()
list(FIND OMNIX_BARESIP_MODULES "srtp" _omnix_mod_srtp)
if(_omnix_mod_srtp EQUAL -1)
  message(FATAL_ERROR "SDK-026: OMNIX_BARESIP_MODULES must include srtp")
endif()

# -----------------------------------------------------------------------------
# baresip (finds re via FindRE + re-config.cmake under third_party/re/cmake)
# -----------------------------------------------------------------------------
add_subdirectory("${OMNIX_BARESIP_SRC}" "${CMAKE_CURRENT_BINARY_DIR}/baresip_build")

# -----------------------------------------------------------------------------
# Omnix C facade (SDK-010)
# -----------------------------------------------------------------------------
add_library(omnix_voice STATIC
  src/omnix_voice.c
  src/omnix_account.c
  src/omnix_call.c
  src/omnix_audio.c
  src/omnix_events.c
  src/omnix_log.c
)
target_include_directories(omnix_voice
  PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
  PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(omnix_voice
  PUBLIC
    baresip
    re
)
# SDK-025: OpenSSL headers for version string (linked via re/baresip).
if(OPENSSL_INCLUDE_DIR)
  target_include_directories(omnix_voice PRIVATE "${OPENSSL_INCLUDE_DIR}")
endif()
if(ANDROID)
  target_link_libraries(omnix_voice PUBLIC log)
endif()

option(OMNIX_BUILD_TESTS "Build native unit tests" OFF)
if(OMNIX_BUILD_TESTS)
  add_executable(test_log_redaction
    "${OMNIX_REPO_ROOT}/tests/native/test_log_redaction.c"
  )
  target_include_directories(test_log_redaction PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
  )
  target_link_libraries(test_log_redaction PRIVATE omnix_voice)

  add_executable(test_lifecycle
    "${OMNIX_REPO_ROOT}/tests/native/test_lifecycle.c"
  )
  target_include_directories(test_lifecycle PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
  )
  target_link_libraries(test_lifecycle PRIVATE omnix_voice)

  add_executable(test_account
    "${OMNIX_REPO_ROOT}/tests/native/test_account.c"
  )
  target_include_directories(test_account PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
  )
  target_link_libraries(test_account PRIVATE omnix_voice)

  add_executable(test_registration
    "${OMNIX_REPO_ROOT}/tests/native/test_registration.c"
  )
  target_include_directories(test_registration PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
  )
  target_link_libraries(test_registration PRIVATE omnix_voice)

  add_executable(test_registration_events
    "${OMNIX_REPO_ROOT}/tests/native/test_registration_events.c"
  )
  target_include_directories(test_registration_events PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
  )
  target_link_libraries(test_registration_events PRIVATE omnix_voice)

  add_executable(test_call_model
    "${OMNIX_REPO_ROOT}/tests/native/test_call_model.c"
  )
  target_include_directories(test_call_model PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
  )
  target_link_libraries(test_call_model PRIVATE omnix_voice)

  add_executable(test_outgoing_call
    "${OMNIX_REPO_ROOT}/tests/native/test_outgoing_call.c"
  )
  target_include_directories(test_outgoing_call PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
  )
  target_link_libraries(test_outgoing_call PRIVATE omnix_voice)

  add_executable(test_incoming_call
    "${OMNIX_REPO_ROOT}/tests/native/test_incoming_call.c"
  )
  target_include_directories(test_incoming_call PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
  )
  target_link_libraries(test_incoming_call PRIVATE omnix_voice)

  add_executable(test_answer_reject
    "${OMNIX_REPO_ROOT}/tests/native/test_answer_reject.c"
  )
  target_include_directories(test_answer_reject PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
  )
  target_link_libraries(test_answer_reject PRIVATE omnix_voice)

  add_executable(test_hangup
    "${OMNIX_REPO_ROOT}/tests/native/test_hangup.c"
  )
  target_include_directories(test_hangup PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
  )
  target_link_libraries(test_hangup PRIVATE omnix_voice)

  add_executable(test_mute
    "${OMNIX_REPO_ROOT}/tests/native/test_mute.c"
  )
  target_include_directories(test_mute PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
  )
  target_link_libraries(test_mute PRIVATE omnix_voice)

  add_executable(test_speaker
    "${OMNIX_REPO_ROOT}/tests/native/test_speaker.c"
  )
  target_include_directories(test_speaker PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
  )
  target_link_libraries(test_speaker PRIVATE omnix_voice)

  add_executable(test_dtmf
    "${OMNIX_REPO_ROOT}/tests/native/test_dtmf.c"
  )
  target_include_directories(test_dtmf PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
  )
  target_link_libraries(test_dtmf PRIVATE omnix_voice)

  add_executable(test_hold
    "${OMNIX_REPO_ROOT}/tests/native/test_hold.c"
  )
  target_include_directories(test_hold PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
  )
  target_link_libraries(test_hold PRIVATE omnix_voice)

  add_executable(test_tls
    "${OMNIX_REPO_ROOT}/tests/native/test_tls.c"
  )
  target_include_directories(test_tls PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
  )
  target_link_libraries(test_tls PRIVATE omnix_voice)

  add_executable(test_srtp
    "${OMNIX_REPO_ROOT}/tests/native/test_srtp.c"
  )
  target_include_directories(test_srtp PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
  )
  target_link_libraries(test_srtp PRIVATE omnix_voice)
endif()

# Helpful build summary
add_custom_target(omnix_native_artifacts ALL
  DEPENDS omnix_voice baresip re
  COMMAND ${CMAKE_COMMAND} -E echo "Omnix native artifacts:"
  COMMAND ${CMAKE_COMMAND} -E echo "  re=$<TARGET_FILE:re>"
  COMMAND ${CMAKE_COMMAND} -E echo "  baresip=$<TARGET_FILE:baresip>"
  COMMAND ${CMAKE_COMMAND} -E echo "  omnix_voice=$<TARGET_FILE:omnix_voice>"
)
