# Implementation Plan: flutter_llama for agents

> Version: 0.1
> Status: APPROVED (owner 2026-10-08, «plan approved»)
> Last Updated: 2026-10-08
> Specifications: `02-specifications.md` v0.1 (approved 2026-10-08; S1–S3 as recommended)

## Summary

The work runs in five phases:

0. Baseline.
1. Shared C++ core, with the existing mobile bridges moved onto it.
2. Dart API: chat, grammar, tools, classify, tokens, info, fit, lifecycle.
3. Desktop: Windows and Linux.
4. Presets, example, docs and release 1.2.0 on the owner's command.

Rules for every phase:

- **Owner's code.** Git belongs to the owner: no git writes. The owner's uncommitted changes in the working tree are
  kept untouched.
- **Where each part is built:**
  - the Linux build, the core ctest, Dart tests and the Android emulator run on this server;
  - macOS and iOS run on the owner's MacBook M4 over SSH (S2), once access is given;
  - Windows runs on an owner Windows machine (still to be named).
- **Close-out.** Every task ends with its tests green and `flutter analyze` showing 0 issues.

## Task Breakdown

### Phase 0: Baseline

#### Task 0.1: Inventory and baseline
- **Description:**
  - build the example for Android on this server;
  - run the existing 70 tests;
  - pick the tiny test model: SmolLM2-135M Q4 (Apache-2.0), downloaded to the test fixture cache, not committed;
  - record the current API surface as a compatibility test.
- **Files:** `test/compat_api_test.dart`, `tool/fetch_test_model.sh`
- **Dependencies:** none
- **Verification:** 70 tests plus the compatibility test are green; the Android example builds.
- **Complexity:** Low

### Phase 1: Shared core

#### Task 1.1: `flutter_llama_core` (C ABI)
- **Description:** extract the logic from `android/src/main/cpp/flutter_llama_bridge.cpp` into
  `src/core/flutter_llama_core.{h,cpp}` and add:
  - `fl_apply_chat_template`, using `llama_chat_apply_template`, or the `common/chat` Jinja path where available;
  - `fl_generate` with a GBNF grammar sampler and a cancel flag;
  - `fl_tokenize_count`, `fl_meta`, `fl_label_logprobs`, `fl_embed`.
- **Files:** `src/core/**`, `src/core/CMakeLists.txt`, `src/core/test/core_test.cpp`
- **Dependencies:** 0.1
- **Verification:** ctest on Linux with the tiny model:
  - the template renders;
  - the grammar output parses as JSON;
  - the token count matches the tokenizer;
  - label log-probs rank an obvious label first;
  - stop works.
- **Complexity:** High

#### Task 1.2: Android bridge onto the core
- **Description:** JNI becomes a thin wrapper over the core (existing names kept) plus the new methods.
  `onTrimMemory` triggers unload.
- **Files:** `android/src/main/cpp/*`, `android/.../FlutterLlamaPlugin.kt`
- **Dependencies:** 1.1
- **Verification:** the example on the Android emulator: the old `generateStream`, then a new chat with a tool call
  and classify.
- **Complexity:** Medium

#### Task 1.3: iOS / macOS bridge onto the core
- **Description:**
  - one shared `llama_cpp_bridge.mm` over the core (it replaces the two identical copies);
  - the Swift plugins get the new methods and memory-warning handling;
  - the xcframework links the core.
- **Files:** `ios/Classes/*`, `macos/Classes/*`, podspecs, `scripts/build_xcframework*.sh`
- **Dependencies:** 1.1
- **Verification:** on the owner's MacBook: macOS example plus iOS simulator, same scenario as 1.2.
- **Complexity:** Medium

### Phase 2: Dart API

#### Task 2.1: Models, errors, routing
- **Description:**
  - `LlamaMessage`, `ChatParams`, `ToolSpec`, `ToolCall`, `ChatChunk`, `ChatResult`, `ModelInfo`, `DeviceFit`,
    `ClassifyResult`, `LlamaError`;
  - `isSupported`;
  - backend routing (channel vs FFI) behind conditional imports, so web builds compile.
- **Files:** `lib/src/models/*`, `lib/src/backend/*`, `lib/flutter_llama.dart`
- **Dependencies:** none (can run in parallel with Phase 1)
- **Verification:** unit tests with a fake backend; a `flutter build web` of a stub app compiles and
  `isSupported == false`.
- **Complexity:** Medium

#### Task 2.2: Grammar
- **Description:** JSON schema → GBNF (types, enums, nested objects, arrays, required / optional); the tool-call
  grammar; the label-choice grammar.
- **Files:** `lib/src/grammar/*`
- **Dependencies:** none
- **Verification:**
  - golden GBNF tests;
  - every grammar is accepted by the core (`GrammarInvalid` never thrown on valid schemas);
  - sampled outputs parse (via the 1.1 ctest).
- **Complexity:** Medium

#### Task 2.3: chat / chatStream with tools
- **Description:**
  - native tool-call parsing per family (Qwen3 / Granite / Llama markers);
  - the grammar fallback;
  - one repair retry;
  - `toolChoice`;
  - the `thinking` flag;
  - usage and stop reasons.
- **Files:** `lib/src/chat/*`
- **Dependencies:** 2.1, 2.2, 1.2 or 1.3 or 3.x for native runs
- **Verification:**
  - unit tests for parsing and repair with recorded outputs;
  - native: Qwen3-0.6B performs a two-tool scenario, then answers.
- **Complexity:** High

#### Task 2.4: classify, tokens, modelInfo, canLoad, lifecycle
- **Description:**
  - `classify` (log-prob and embedding methods);
  - `countTokens` / `countChatTokens`;
  - `modelInfo` from GGUF meta;
  - `canLoad` with per-platform memory APIs;
  - lifecycle: background unload, idle timeout, memory pressure.
- **Files:** `lib/src/*`, platform code
- **Dependencies:** 2.1, 1.x
- **Verification:**
  - unit tests (fake clock, fake memory);
  - braindler classify benchmark on a phone-class device (Android emulator figure plus one real device if the owner
    has one), with a target under 50 ms after load.
- **Complexity:** Medium

### Phase 3: Desktop

#### Task 3.1: Linux FFI plugin
- **Description:** `linux/` FFI plugin. CMake builds the core and llama.cpp: CPU by default, Vulkan optional. Dart
  FFI bindings with streaming through `NativeCallable.listener`.
- **Files:** `linux/**`, `lib/src/ffi/*`, `pubspec.yaml`
- **Dependencies:** 1.1, 2.1
- **Verification:** the Linux example on this server runs the 2.3 / 2.4 scenarios.
- **Complexity:** Medium

#### Task 3.2: Windows FFI plugin
- **Description:** `windows/` FFI plugin built with MSVC 2022: CPU, plus Vulkan and CUDA as opt-in CMake options.
- **Files:** `windows/**`
- **Dependencies:** 3.1
- **Verification:** the Windows example on the owner's Windows machine, same scenarios. Until a machine is available
  the task is code-complete with a CI-less note.
- **Complexity:** Medium

#### Task 3.3: macOS parity check
- **Description:** confirm macOS through the channel path has every feature (done in 1.3), and record the Metal
  numbers.
- **Dependencies:** 1.3, 2.x
- **Verification:** the scenario on the MacBook M4, with Qwen3-8B tokens per second recorded.
- **Complexity:** Low

### Phase 4: Presets, example, docs, release

#### Task 4.1: Open-model presets and catalogue
- **Description:**
  - presets: Qwen3 0.6B / 1.7B / 4B / 8B, Granite 2B / 8B, Phi-4-mini, SmolLM2-360M, with SPDX licence, base model,
    RAM, download size, languages, `goodAtTools`, tasks;
  - each licence is verified from its model card, with the link recorded;
  - braindler and shridhar are removed from the built-in list (braindler moves to dropexpired via
    `ModelCatalog.register`);
  - `ModelCatalog.register`.
- **Files:** `lib/src/models/preset_model.dart`, `lib/src/catalog.dart`, `doc/models.md`
- **Dependencies:** 2.1
- **Verification:**
  - a test that every built-in preset is Apache-2.0 or MIT;
  - a test that the catalogue merges product presets.
- **Complexity:** Low

#### Task 4.2: Example and docs
- **Description:**
  - example screens: chat with tools, classify, device fit, model download;
  - README sections for chat / tools / classify / desktop, with "open models only" and the licence;
  - a migration note from 1.1.
- **Dependencies:** 2.x, 3.x, 4.1
- **Verification:** the example runs on every available platform; links in the docs resolve.
- **Complexity:** Low

#### Task 4.3: Release 1.2.0 (owner's command)
- **Description:** CHANGELOG, `.pubignore` size check, `flutter pub publish --dry-run`. The publish itself happens
  only on the owner's command.
- **Dependencies:** all
- **Verification:** the dry-run is clean and the package size is within the 1.1.2 budget plus the new sources.
- **Complexity:** Low

## Dependency Graph

```
0.1 → 1.1 → 1.2 ──┐
          → 1.3 ──┤
2.1 → 2.2 → 2.3 ──┼→ 2.4 → 3.3
          1.1 → 3.1 → 3.2
2.x + 3.x → 4.1 → 4.2 → 4.3 (owner)
```

## Risks

| Risk | Mitigation |
|---|---|
| A Jinja template is not renderable by llama.cpp `945501f5e` | Family templates in Dart; upgrade llama.cpp only as its own task (S3) |
| Small models break the JSON | Grammar-constrained sampling makes the output parseable by construction; one repair retry |
| No Windows machine | 3.2 is code-complete and CI-less until the owner provides one |
| No MacBook access yet | Phases 0–2 and 3.1 run on this server; 1.3 / 3.3 wait for access |
| Changing the owner's mobile bridges | Thin wrappers keep the JNI / channel names; the compatibility test from 0.1 guards the old API |

## Rollback

Version 1.2.0 is additive: consumers can pin 1.1.2. The core refactor stays behind the same channel names. If a
platform regresses, its bridge can keep the old code path, reached through a build flag, until it is fixed.
