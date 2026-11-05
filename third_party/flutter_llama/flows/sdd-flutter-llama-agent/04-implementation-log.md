# Implementation Log: flutter_llama for agents

> Plan: `03-plan.md` v0.1 (approved 2026-10-08)

## Progress

| Task | Status | Notes |
|---|---|---|
| 0.1 Baseline | Done (Android example build deferred to 1.2) | 71 tests green; compatibility test; tiny model script |
| 1.1 Core | Done | `src/core`: C ABI, Linux build, 20 core checks green |
| 2.2 Grammar | Done | JSON schema → GBNF, tool-call and label grammars; 3 unit tests; native check: 6 / 6 outputs parse |
| 1.2, 1.3, 2.1, 2.3–4.3 | Not started | |

## Session 2026-10-08 — Claude Code

- **0.1**
  - The existing suite passes 71 / 71 (host Flutter 3.47.6).
  - `flutter analyze` baseline: 308 issues. All errors are in `example/` (stale multimodal demos, downloader test);
    `lib/` has only infos (`avoid_print` etc.). New code must add 0.
  - Flutter 3.47 rewrote `analysis_options.yaml` on `pub get`: it added excludes for `build/`, `android/`, `ios/`,
    `macos/`. This is the tool's own automatic upgrade; the change is kept and noted for the owner.
  - `test/compat_api_test.dart` freezes the 1.1.x channel / method names and payload keys.
  - `tool/fetch_test_model.sh` downloads SmolLM2-135M-Instruct Q4_K_M (Apache-2.0, 100 MB) to
    `~/.cache/flutter_llama/test_models` (not in the package).
  - The Android example build is deferred: no Android SDK on this host; the SDK image needs the NDK. It is done in 1.2.
- **1.1 core** (`src/core/flutter_llama_core.{h,cpp}`, `src/core/CMakeLists.txt`, `src/core/test/core_test.cpp`)
  - C ABI with no global state (a handle per model):
    - `fl_load` / `fl_free`;
    - `fl_apply_chat_template` (the model's own template, or a built-in name / template string; buffer-size
      protocol);
    - `fl_generate`: grammar sampler, repeat penalty, stop strings held back across pieces, complete UTF-8 pieces
      only, cancel from the callback or `fl_stop`, usage + stop reason, typed errors;
    - `fl_tokenize_count`, `fl_meta`, `fl_facts`;
    - `fl_label_logprobs`: the prompt is decoded once, multi-token labels go on a second sequence;
    - `fl_embed`: pooled, or mean over tokens, L2-normalised.
  - **Human-factor fixes from the 1.1.2 Android bridge** (not carried over):
    - the context memory was never cleared, so positions grew across calls until the context overflowed;
    - `repeatPenalty` was accepted but ignored.
  - Built on Linux with the vendored llama.cpp `945501f5e` (CPU, `GGML_NATIVE`). 20 checks pass on SmolLM2-135M:
    - facts / meta;
    - template + buffer protocol;
    - greedy generation, stable across 5 repeats (the clear fix);
    - GBNF output and an invalid-grammar error;
    - stop strings, cancel;
    - label log-probs ranking (positive > negative on an obvious review);
    - embeddings (unit norm; similar sentences closer);
    - context overflow error.
- **2.2 grammar** (`lib/src/grammar/gbnf.dart`, `test/grammar_test.dart`)
  - `JsonSchemaGrammar.fromSchema` supports:
    - type (single or a list), enum, const, anyOf / oneOf;
    - objects: required first in declared order, then optional ones;
    - an all-optional object as any in-order subset;
    - arrays with min / max items ≤ 32;
    - an empty schema meaning any JSON value.
    - Unsupported input raises `GrammarSchemaException`.
  - `toolCallGrammar` and `labelChoiceGrammar`. Unit tests: 3. `flutter analyze`: 0 issues on the new files.
  - **Native check** (`src/core/test/gbnf_run.cpp` + `test/tool_dump_grammars.dart`, run only with `FL_GBNF_OUT`):
    - the core accepted all three grammars;
    - 6 / 6 sampled outputs from SmolLM2-135M parse as JSON (object schema, tool call, all-optional object).
    - The tiny model sometimes picks the wrong tool by meaning (expected at 135M); the structure is guaranteed.

- **2.1 models, errors, routing** (`lib/src/models/chat.dart`, `lib/src/backend/*`, `lib/src/ffi/bindings.dart`)
  - Models as in the spec: `LlamaMessage` / `LlamaRole`, `ToolSpec`, `ToolCall`, `ToolChoice` (auto / none / required /
    named), `ChatTemplate`, `ChatParams`, `ChatChunk` (`ChatText` / `ChatToolCalls` / `ChatDone`), `ChatResult`,
    `ChatUsage`, `ModelInfo`, `DeviceFit`, `ClassifyParams`, `ClassifyResult`, and the sealed `LlamaError` family.
  - `LlamaBackend` interface with three implementations:
    - `ChannelBackend` (Android / iOS / macOS). Loading keeps the 1.1 `loadModel` payload. The new `core.*` methods
      and the `flutter_llama/core_stream` event protocol are defined in `CoreChannel`; the Kotlin and Swift sides
      come in 1.2 / 1.3. `PlatformException` codes map to typed errors.
    - `FfiBackend` (Windows / Linux). Hand-written bindings of `flutter_llama_core.h`. Blocking calls (load, generate,
      label log-probs, embed) run on helper isolates with an isolate-local callback; pieces return through a
      `SendPort`. Calls are serialised per model.
    - `UnsupportedBackend` (web).
  - Selection: `select.dart` with a conditional import (`dart.library.io`), so web builds never see `dart:ffi`.
  - `FlutterLlama.isSupported`, `FlutterLlama.backend`, and `debugBackend` for tests.
  - **Desktop compatibility.** On Linux / Windows the 1.1 calls (`loadModel`, `generate`, `generateStream`,
    `unloadModel`, `getModelInfo`, `stopGeneration`) go through the FFI backend, but only when the core library
    loads. Without it they keep the 1.1 channel path, so the owner's channel-mocking tests are unchanged.
  - **Deviations:**
    - pubspec: `ffi: ^2.1.0`, SDK `^3.4.0` / Flutter `>=3.22.0` (isolate-local native callbacks);
    - the core's default thread count is now half the logical cores, capped at 8 for generation. Using every logical
      core made ggml's spinning barriers collapse on a busy host: 2 tokens in 15 s at load 42 on 28 cores, against
      about 10 tokens/s after the change.
  - **Verification:**
    - `test/backend_routing_test.dart`: 6 tests with `FakeBackend` (desktop 1.1 path, channel payload keys, typed
      errors, stop reasons);
    - `test/ffi_live_test.dart`: 4 tests against `libflutter_llama_core.so` + SmolLM2-135M, run only with
      `FLUTTER_LLAMA_CORE_LIB` and `FL_TEST_MODEL`. Covers facts / meta / template / tokens, streaming with a
      grammar (JSON parses), stop → `cancelled`, label log-probs, and the embeddings guard;
    - a web stub app builds (`flutter build web`), and in Chrome `isSupported == false` while `loadModel` returns
      false;
    - core ctest still passes after the thread change;
    - full suite: 82 passed, 4 skipped; `flutter analyze` on the new files: 0 issues.
- **2.3 chat / chatStream with tools** (`lib/src/chat/chat_engine.dart`, `lib/src/chat/families.dart`)
  - `FlutterLlama.chat` / `chatStream`, through `LlamaChatEngine` over any backend. Calls are serialised; the model
    traits (template, architecture, name) are cached per load.
  - **Modes:**
    - plain chat (no tools, or `toolChoice: none`); `grammar` / `jsonSchema` constrain it;
    - native tools when the GGUF template renders Hermes / Qwen `<tool_call>`:
      - the tools block goes into the system message, in the Qwen template's wording;
      - assistant calls are replayed as `<tool_call>` blocks;
      - tool results go back as `<tool_response>`, with consecutive results in one user turn;
    - the grammar fallback on every other instruction model:
      - a compact tool list goes into the system message;
      - sampling is constrained to `{"tool", "arguments"} | {"answer"}`;
      - the answer text streams as it is generated (`AnswerStreamer` decodes the JSON string incrementally).
  - **Parsing.** `parseNativeToolCalls` reads Hermes / Qwen blocks (several per reply), Granite `<|tool_call|>[…]`,
    and Llama-style bare JSON. Unknown tool names count as a parse failure.
  - **Repair.** One retry, constrained by `nativeToolCallGrammar` (new in `gbnf.dart`) or the tool grammar, with
    twice the `maxTokens`. If that fails too, `ToolParseFailed` (`tool_parse_failed`, with the raw reply).
  - **`toolChoice`:** `required` and `named` narrow the grammar; `named` offers only that tool.
  - **`thinking`:** Qwen3 gets `/think` or `/no_think`; a leading `<think>…</think>` is hidden from the stream and
    the result.
  - **No GGUF template** (GPT-2 style, such as braindler): plain `User:` / `Assistant:` turns with a `\nUser:` stop.
  - **Usage.** Prompt and completion tokens are summed over attempts. The stop reason is `toolCall` when there are
    calls.
  - **Verification:**
    - `test/chat_test.dart`: 13 tests on recorded outputs (families, the three parsers, answer streaming, think
      hiding, native and grammar modes, tool replay, repair, ToolParseFailed, `toolChoice`, JSON schema, the
      no-template case, serialisation, ModelNotLoaded);
    - `test/chat_live_test.dart` (FFI, Linux):
      - **Qwen3-0.6B Q8_0** (official Qwen GGUF, Apache-2.0): round 0 made two calls in one reply, `get_weather` and
        `get_time` for Tampa (202 / 45 tokens). Round 1 answered "The current weather in Tampa is sunny with a
        temperature of 84°F, and the local time is 14:05." with no `<think>` leak;
      - SmolLM2-135M grammar fallback with `toolChoice: required`: the call parses by construction;
    - full suite: 95 passed, 6 skipped (live tests without env); `flutter analyze` on the new files: 0 issues.
- **2.4 classify, tokens, modelInfo, canLoad, lifecycle**
  - `classify(text, labels, params:)` (`lib/src/chat/classify.dart`):
    - **log-prob method (default):** the system prompt holds the instructions and "reply with exactly one of …";
      few-shot examples become user / assistant turns. The label log-probabilities come from the core (shared prefix
      decoded once) and are softmaxed. For Qwen3 the think block is closed before the label; without a template the
      label follows `Assistant: `;
    - **embedding method:** centroids of the examples and cosine similarity (temperature 0.05); every label needs
      examples.
  - `countTokens` and `countChatTokens` (the rendered prompt, with tools and template), `embed`.
  - `modelInfo()` builds `ModelInfo` from the core's facts and GGUF meta: architecture, quantization from llama.cpp's
    file-type name (`Q4_K - Medium` → `Q4_K_M`), template family, native tools, `general.*`.
  - `canLoad(ModelRef)` (`lib/src/fit/*`):
    - `ModelRef.file`: a pure-Dart GGUF header reader (metadata only, arrays skipped) gives the KV-cache shape. Need
      = file × 1.2 + the f16 KV for the context;
    - `ModelRef.download`: free disk first, then RAM (`ramBytes` or the estimate);
    - memory and disk: Linux `/proc/meminfo` `MemAvailable` + `statvfs`; Windows `GlobalMemoryStatusEx` +
      `GetDiskFreeSpaceExW`; Android / iOS / macOS through `core.memory` / `core.freeDisk` (Kotlin / Swift in 1.2 /
      1.3; until then `unknown_memory`, ok);
    - web: `unsupported_platform` (the reader and probes sit behind conditional imports).
  - **Lifecycle** (`lib/src/lifecycle.dart`): `LlamaLifecycle` with `unloadOnBackground`, `idleTimeout` and
    `onMemoryPressure`. Defaults: mobile on with 5 min idle; desktop off.
    - `FlutterLlama` watches the app lifecycle, memory pressure and an idle timer reset after every call.
    - An automatic unload stops a running generation first.
    - The next call reloads the model with the last `LlamaConfig`.
  - **Cancellation.** Cancelling a generation subscription stops the native run on FFI and on channels
    (`core.stop`). A run cancelled while queued is skipped, because the core resets its stop flag when a generation
    starts.
  - **Verification:**
    - `test/agent_extras_test.dart`: 12 tests (classify both methods, the Qwen3 prompt, helpers, canLoad file /
      download / disk / unknown memory / unsupported, Linux probes, the GGUF header of SmolLM2, modelInfo,
      countTokens, lifecycle with fake_async (idle unload → reload on the next call, memory pressure, background),
      platform defaults);
    - the live FFI tests gained a cancel-by-subscription case (5 / 5);
    - **Not done:** the phone-class < 50 ms classify benchmark needs the Android bridge (1.2) and a device. On this
      loaded server (load ≈ 40 / 28 cores) classify took 2.5 s (SmolLM2-135M, 2 labels) and 6.8 s (Qwen3-0.6B, 2
      labels) in the Linux app. These numbers are not representative.
  - **Observation (model quality, not mechanics).** Qwen3-0.6B labelled LienDeed parcel statuses (`redeemed` /
    `for_sale` / `unknown`) as `unknown` even with few-shot examples, while sentiment works. Advice for products: no
    catch-all label on ≤ 1B models; use a fine-tuned classifier (dropexpired's braindler plan) or ≥ 1.7B.
- **3.1 Linux FFI plugin** (`linux/CMakeLists.txt`, `windows/CMakeLists.txt`, `src/core/CMakeLists.txt`, pubspec
  `linux` / `windows: ffiPlugin: true`)
  - The plugin builds `src/core` plus llama.cpp statically and bundles `libflutter_llama_core.so` (3.6 MB,
    `--exclude-libs,ALL`) next to the app. Vulkan is opt-in (`FLUTTER_LLAMA_VULKAN`; Windows also
    `FLUTTER_LLAMA_CUDA`).
  - Binaries are portable by default (`GGML_NATIVE` off; `FL_NATIVE=ON` for local tuning). The core and ggml are
    optimised in debug app builds too: at `-O0` a debug run did not finish in 10 minutes.
  - **llama.cpp source.** The checkout next to the package (git / development) is used when present. Otherwise CMake
    fetches the pinned commit `945501f5e` (a pub.dev install: `llama.cpp/` is in `.pubignore`). **Finding for 4.3:**
    the 1.1.2 Android CMake also points at `../llama.cpp`, so a pub.dev install of 1.1.2 cannot build Android
    natively. Same fix to apply in 1.2.
  - **Toolchain.** This server has no clang / ninja / GTK and no sudo. The build and test run in a Docker image
    (`ubuntu:24.04` + clang 18, ninja, GTK 3, xvfb), with the host Flutter SDK mounted.
  - **Verification.** A check app (job scratch, not in the repo) with `integration_test/scenario_test.dart` ran
    under xvfb on Linux, using the bundled library (no env override):
    - `isSupported`; `canLoad` (need 174 MB of 24 GB available); 1.1 `generate` → " Paris.";
    - `modelInfo` = llama Q4_K_M chatml ctx 2048; `countTokens`; classify (SmolLM2) positive 0.66;
    - Qwen3-0.6B: round 0 made two calls (`get_weather`, `get_time`), round 1 answered with both facts; classify
      negative 0.84.
    - **2 / 2 passed.**
  - The example now has `linux/` (from `flutter create --platforms=linux`). **Pre-existing:** the owner's example
    does not compile (stale `PresetModel` imports, `ggufFiles`, multimodal `prompt` arguments) and was left as is.
    Task 4.2 rewrites the example screens.
- **4.1 Open-model presets and catalogue** (`lib/src/catalog.dart`, `lib/src/models/preset_model.dart`,
  `doc/models.md`)
  - `PresetModel` gained `license`, `baseModel`, `ramBytes`, `downloadBytes`, `goodAtTools`, `tasks` (`LlamaTask`)
    and `cardUrl`. They are optional, so the 1.1 constructor still works; `copyWith` covers them.
  - **`OpenModels`** (8 presets, GGUF Q4_K_M):
    - Qwen3 0.6B / 1.7B (unsloth quantisations of the official weights), Qwen3 4B / 8B (official Qwen GGUF);
    - Granite 3.3 2B / 8B (official IBM GGUF);
    - Phi-4-mini (unsloth, MIT);
    - SmolLM2-360M (bartowski).
    - Licences were read from the Hugging Face API card data on 2026-10-08: Apache-2.0 for all except Phi-4-mini
      (MIT). Download sizes are the exact byte counts from the API.
  - **`ModelCatalog`:** `builtIn` (open models only), `register` (same id + file replaces), `all`, `forTask`,
    `debugReset`.
  - The 1.1 `PresetModels` (braindler, shridhar) are kept for compatibility (`compat_api_test`) and are not in
    `builtIn`. Removing them is proposed for 2.0. braindler goes to dropexpired via `register`.
  - `doc/models.md`: the preset table, per-platform recommendations, tool and classify guidance, product presets.
  - **Verification.** `test/catalog_test.dart`: 3 tests (every built-in preset is Apache-2.0 / MIT with a card, sizes
    and a single `.gguf`; braindler / shridhar absent; register / replace / `forTask`; 1.1 presets still present).
- **1.2 (partial): Android CMake version (2026-10-09, found by the LienDeed Android release build).**
  `android/build.gradle` pinned CMake 3.18.1, but the vendored llama.cpp's `ggml-vulkan` needs ≥ 3.19, so the 1.1.2
  Android native build fails configure. Bumped to 3.22.1 (Android SDK package). The JNI-onto-core work of 1.2 is still
  open.
  The Android build also needs, for ggml-vulkan: host ninja + `glslc` on PATH (the vulkan-shaders-gen host
  sub-build), and the C++ Vulkan headers, which the NDK lacks. `android/src/main/cpp/CMakeLists.txt` now fetches
  Khronos Vulkan-Headers v1.4.309 (Apache-2.0) when Vulkan is enabled.
  Then the link failed: ggml-vulkan needs Vulkan 1.1 (`vkGetPhysicalDeviceFeatures2`), which the NDK's libvulkan
  exports from API 28 only, while the plugin targets android-24. Vulkan is now enabled only when
  `ANDROID_PLATFORM_LEVEL ≥ 28`; at 24 the CPU (NEON) backend builds. **Open in 1.2:** GPU on Android (minSdk 28 or
  loading Vulkan dynamically).
- **1.2 (partial): Android GPU through `GGML_BACKEND_DL`; R8 rules (2026-10-10).**
  - The Vulkan-at-API-28 gate above is replaced by dynamic backends: `GGML_BACKEND_DL=ON` builds `libggml-cpu.so`
    and `libggml-vulkan.so` as modules. The bridge loads them by name once (`ggml_backend_load`), so minSdk stays 24:
    devices without Vulkan 1.1 run on CPU. A new JNI `nativeBackendInfo()` is reported as `backends` in
    `getModelInfo`.
  - **Release crash found and fixed.** The plugin had no consumer R8 rules. In an app's release build R8 removed the
    `ModelInfo` / `GenerationResult` constructors that the bridge looks up by name, so the first `getModelInfo` crashed
    with `NoSuchMethodError`. This affected every release app using the plugin. Added `android/consumer-rules.pro`
    (keeps those classes and the native methods) and `consumerProguardFiles` in `android/build.gradle`.
  - **Device benchmark** (release APK, Qwen3-0.6B Q4_K_M, 2048 context, 4 threads, 96 max tokens, 2 runs each):

    | Device | Backends found | CPU (`gpuLayers 0`) | Vulkan (`gpuLayers 99`) |
    |---|---|---|---|
    | Samsung A07 (MT6789, Mali-G57 MC2, Android 16) | `CPU;Vulkan0 (Mali-G57 MC2)` | 7.3 / 6.5 tok/s, load 1.0 s | 2.0 / 2.0 tok/s, load 1.7 s |

    On this Mali GPU, ggml-vulkan is about 3× slower than the CPU. **Recommendation:** default to CPU and offload only
    on GPUs known to be faster (Adreno 6xx+, to be measured). The Poco X3 Pro (Adreno 640) is not measured yet:
    MIUI refuses adb installs until "Install via USB" is enabled on the phone (needs the owner's Mi account).
- **1.2 (partial): GPU "auto" on Android (2026-10-11).**
  - `nGpuLayers < 0` (the default `-1`) now means auto in `flutter_llama_bridge.cpp`: every layer goes to a Vulkan
    GPU unless the device is a Mali or PowerVR, which get 0, as do devices with no GPU. A count ≥ 0 is used as given.
  - Based on the A07 benchmark (Mali-G57: 2.0 vs 6.5–7.3 tok/s on the CPU).
  - The bridge logs the decision (`GPU layers auto: …`). The Poco (Adreno 640) is still to be measured.
- **4.2 Example and docs (2026-10-11).**
  - `example/lib/agent/agent_screen.dart` (new), reached from a robot button in the example's app bar:
    - the open-model catalogue with `canLoad` before download, and load with auto GPU, showing `backends`;
    - chat with a tool (`utc_now`, a tool-result round trip);
    - classify over fixed labels with scores.
  - `doc/agent.md`: load, fit, GPU policy, lifecycle, chat and tools, structured output, streaming, classify,
    desktop, "open models only", migration from 1.1, and the R8 note. README gets an "Agent API (1.2)" section.
  - **The owner's example did not compile; fixed minimally:**
    - `GenerationParams(prompt: '')` in the multimodal demos (the input carries the text);
    - the missing `flutter_llama` imports in two screens;
    - `ggufFiles` → `files`;
    - `generationTime` → `generationTimeMs`;
    - the template `widget_test` / `getPlatformVersion` checks replaced by real ones;
    - the preset test expects files only for Hugging Face presets.
  - **Verification:**
    - `flutter analyze` for the example: 0 errors (269 pre-existing infos / warnings);
    - example tests 9/9;
    - plugin tests 110 pass, 7 skipped;
    - `flutter build linux --debug` of the example in the `fl-linux-build` image: built.
  - Windows / macOS / iOS / Android runs of the example wait for those machines; the Android build compiles in
    the LienDeed AABs.
- **4.3 Release 1.2.0 (owner command 2026-10-11).**
  - Version 1.2.0 and the CHANGELOG entry.
  - Android CMake now falls back to FetchContent of llama.cpp at the pinned commit `945501f5e`, as src/core already
    does: a pub.dev install has no `llama.cpp/` (excluded by `.pubignore`), so 1.1.2 could not build Android from
    pub.dev.
  - The dry run passed with 2 warnings: the gitignored llama.cpp checkout and files modified in git (the owner's and
    mine).
  - Published 2026-10-11, archive 20 MB.
  - **Verified:** the bench app was built (release, arm64, 47.5 MB) against a copy of the package made like the
    pub.dev archive, with `.pubignore` applied and no `llama.cpp/`. CMake fetched llama.cpp at the pinned commit.
    1.2.0 builds on Android from pub.dev.
  - Note for later: Flutter warns that the plugin applies the Kotlin Gradle Plugin; migrating to Built-in Kotlin is a
    1.2.x / 1.3 item.
