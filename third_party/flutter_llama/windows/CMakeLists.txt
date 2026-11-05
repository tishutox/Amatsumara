# flutter_llama Windows FFI plugin (sdd-flutter-llama-agent 3.2): MSVC 2022; CPU by default, Vulkan / CUDA opt-in
# (set(FLUTTER_LLAMA_VULKAN ON) or set(FLUTTER_LLAMA_CUDA ON) in the app's windows/CMakeLists.txt before the plugins).
cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "flutter_llama")
project(${PROJECT_NAME} LANGUAGES C CXX)

option(FLUTTER_LLAMA_VULKAN "Build ggml with the Vulkan backend" OFF)
option(FLUTTER_LLAMA_CUDA "Build ggml with the CUDA backend" OFF)
set(GGML_VULKAN ${FLUTTER_LLAMA_VULKAN} CACHE BOOL "" FORCE)
set(GGML_CUDA ${FLUTTER_LLAMA_CUDA} CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)

# llama.cpp at -O0 (a debug app build) is unusably slow: the core and ggml are optimised in every configuration.
set(CMAKE_C_FLAGS_DEBUG "/MDd /O2 /Ob2")
set(CMAKE_CXX_FLAGS_DEBUG "/MDd /O2 /Ob2")

add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../src/core" "${CMAKE_CURRENT_BINARY_DIR}/core")

set(flutter_llama_bundled_libraries
  $<TARGET_FILE:flutter_llama_core>
  PARENT_SCOPE
)
