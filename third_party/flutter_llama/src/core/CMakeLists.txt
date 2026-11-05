# flutter_llama core (sdd-flutter-llama-agent 1.1). Builds the vendored llama.cpp and the C ABI library used by the
# desktop FFI plugins; the mobile bridges compile flutter_llama_core.cpp into their own libraries.
#   cmake -S src/core -B build/core -DFL_CORE_TESTS=ON && cmake --build build/core -j && ctest --test-dir build/core
cmake_minimum_required(VERSION 3.14)
project(flutter_llama_core CXX C)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
option(FL_CORE_TESTS "Build the core tests" OFF)

set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(LLAMA_CURL OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
# Portable binaries by default (no -march=native); FL_NATIVE=ON for a local build tuned to this CPU.
option(FL_NATIVE "Tune ggml for the build machine's CPU" OFF)
set(GGML_NATIVE ${FL_NATIVE} CACHE BOOL "" FORCE)

# llama.cpp: the checkout next to the package (git / development), else the pinned commit (a pub.dev install, where
# llama.cpp/ is excluded by .pubignore).
set(FL_LLAMA_CPP_COMMIT 945501f5ea4b8ca56b181ecb035e9ee3fb31f432)
set(FL_LLAMA_CPP_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../llama.cpp" CACHE PATH "llama.cpp source directory")
if(EXISTS "${FL_LLAMA_CPP_DIR}/CMakeLists.txt")
  add_subdirectory(${FL_LLAMA_CPP_DIR} ${CMAKE_CURRENT_BINARY_DIR}/llama.cpp EXCLUDE_FROM_ALL)
else()
  include(FetchContent)
  FetchContent_Declare(llama_cpp GIT_REPOSITORY https://github.com/ggml-org/llama.cpp.git GIT_TAG ${FL_LLAMA_CPP_COMMIT})
  FetchContent_GetProperties(llama_cpp)
  if(NOT llama_cpp_POPULATED)
    FetchContent_Populate(llama_cpp)
    add_subdirectory(${llama_cpp_SOURCE_DIR} ${llama_cpp_BINARY_DIR} EXCLUDE_FROM_ALL)
  endif()
endif()

add_library(flutter_llama_core SHARED flutter_llama_core.cpp)
target_include_directories(flutter_llama_core PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(flutter_llama_core PRIVATE llama)
set_target_properties(flutter_llama_core PROPERTIES CXX_VISIBILITY_PRESET hidden)
if(UNIX AND NOT APPLE)
  # Everything static except libc / libstdc++: one .so to bundle.
  target_link_options(flutter_llama_core PRIVATE -Wl,--exclude-libs,ALL)
endif()

if(FL_CORE_TESTS)
  enable_testing()
  add_executable(core_test test/core_test.cpp)
  target_link_libraries(core_test PRIVATE flutter_llama_core)
  add_test(NAME core_test COMMAND core_test)
  set_tests_properties(core_test PROPERTIES ENVIRONMENT "FL_TEST_MODEL=$ENV{FL_TEST_MODEL}")
endif()
if(FL_CORE_TESTS)
  add_executable(gbnf_run test/gbnf_run.cpp)
  target_link_libraries(gbnf_run PRIVATE flutter_llama_core)
endif()
