# flutter_llama Linux FFI plugin (sdd-flutter-llama-agent 3.1): builds the shared core (and the vendored llama.cpp,
# statically) and bundles libflutter_llama_core.so next to the app. CPU by default; Vulkan opt-in with
# set(FLUTTER_LLAMA_VULKAN ON) in the app's linux/CMakeLists.txt before the plugins are added.
cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "flutter_llama")
project(${PROJECT_NAME} LANGUAGES C CXX)

option(FLUTTER_LLAMA_VULKAN "Build ggml with the Vulkan backend" OFF)
set(GGML_VULKAN ${FLUTTER_LLAMA_VULKAN} CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)

# llama.cpp at -O0 (a debug app build) is unusably slow: the core and ggml are optimised in every configuration.
set(CMAKE_C_FLAGS_DEBUG "-O2")
set(CMAKE_CXX_FLAGS_DEBUG "-O2")

add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../src/core" "${CMAKE_CURRENT_BINARY_DIR}/core")

# Flutter bundles these next to the executable (lib/), where DynamicLibrary.open('libflutter_llama_core.so') finds them.
set(flutter_llama_bundled_libraries
  $<TARGET_FILE:flutter_llama_core>
  PARENT_SCOPE
)
