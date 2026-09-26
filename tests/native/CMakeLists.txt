# SDK-052: canonical host test entry.
# Linux CI: cmake -S tests/native -B build/tests -DCMAKE_BUILD_TYPE=Debug
#           cmake --build build/tests
#           ctest --test-dir build/tests --output-on-failure
cmake_minimum_required(VERSION 3.22)
project(omnix_native_tests C CXX)

enable_testing()
set(OMNIX_BUILD_TESTS ON CACHE BOOL "Build native unit tests" FORCE)

add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../../cpp"
                 "${CMAKE_CURRENT_BINARY_DIR}/cpp")
