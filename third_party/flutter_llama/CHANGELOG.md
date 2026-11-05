# Changelog

All notable changes to this project will be documented in this file.

## [1.2.1] - 2026-10-11

### Fixed
- **Android 16 KB page sizes.** The native libraries (`libllama`, `libggml*`, the bridge) are now linked with 16 KB
  LOAD alignment whatever NDK the app uses (`-Wl,-z,max-page-size=16384`, `ANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES`).
  With NDK 27 or older they had 4 KB alignment, which Android 15+ devices with 16 KB pages flag and Google Play
  rejects.

## [1.2.0] - 2026-10-11

### Added
- **Agent API** ([doc/agent.md](doc/agent.md)):
  - `chat` / `chatStream` with the model's own template, tool calls constrained by grammar (`ToolSpec`, `ToolChoice`),
    JSON-schema / GBNF output, and reasoning on or off;
  - `classify` (label log-probabilities or embeddings), `countTokens`, `countChatTokens`, `embed`, `modelInfo`;
  - `canLoad`: whether a model fits the device's memory and disk before downloading;
  - `LlamaLifecycle`: unload on background, idle or memory pressure.
- **Open-model catalogue** `ModelCatalog` / `OpenModels`: Qwen3, Granite 3.3, Phi-4-mini and SmolLM2, Apache-2.0 or MIT
  only, with licence, sizes and tasks ([doc/models.md](doc/models.md)).
- **Desktop.** Linux through FFI onto the shared core (`src/core`). The Windows build files are included.
- **Android GPU.**
  - The CPU and Vulkan backends are separate modules loaded at run time, so minSdk stays 24.
  - `nGpuLayers: -1` is auto: it offloads only where the GPU beats the CPU (Mali and PowerVR stay on the CPU).
  - `getModelInfo()['backends']` lists the devices.
- The example app has an agent tour (open models, chat with a tool, classify).

### Fixed
- Android release builds: consumer R8 rules keep the JNI result classes. Before, the first `getModelInfo` crashed
  with `NoSuchMethodError` under R8.
- Android, Linux and Windows build from a pub.dev install: CMake fetches llama.cpp at the pinned commit
  (`945501f5e`) when the checkout is not next to the package. Android needs CMake 3.22.1.

### Changed
- Requires Dart 3.4 / Flutter 3.22.
- The 1.1 API (`loadModel`, `generate`, `generateStream`, `PresetModels`) is unchanged.
- The repository moved to GitLab, and native binaries are no longer committed. GitLab CI builds the iOS / macOS
  llama.cpp libraries (`tool/build_apple_libs.sh`) and attaches them to each release. The podspecs fetch them on
  `pod install` (`tool/fetch_apple_libs.sh`). The bundled example model was removed; download it from the model manager.

## [1.1.2] - 2025-01-28

### Changed
- Optimized package size by excluding debug symbols and build artifacts
- Added comprehensive .pubignore to reduce package size from 234 MB to 20 MB

## [1.1.1] - 2025-01-28

### Fixed
- Fixed package dependencies: moved `http`, `path`, and `path_provider` from `dev_dependencies` to `dependencies` for proper pub.dev publishing
- Resolved package validation errors for service dependencies

### Changed
- Updated package structure for better dependency management

## [1.0.1] - 2025-01-27

### Fixed
- Fixed macOS library build artifacts for pub.dev publishing
- Removed unused imports in multimodal implementation
- Removed unnecessary library name declaration
- Improved .pubignore to reduce package size

### Changed
- Updated package metadata

## [1.0.0] - 2025-01-27

### Added
- Initial stable release
- Full support for llama.cpp GGUF models on iOS and macOS
- GPU acceleration via Metal
- CPU optimization via Accelerate framework
- Streaming text generation
- Batch processing support
- Multiple model format support
- Comprehensive documentation
- Example application with demos
- Integration tests

## [0.1.1] - 2025-01-26

### Added
- Multimodal support (vision models)
- Enhanced model loading
- Improved error handling

## [0.1.0] - 2025-01-25

### Added
- Initial beta release
- Basic llama.cpp integration
- iOS and macOS platform support
- Model loading and text generation
- Basic configuration options

