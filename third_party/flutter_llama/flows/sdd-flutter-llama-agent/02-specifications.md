# Specifications: flutter_llama for agents (chat, tools, classify, desktop)

> Version: 0.1
> Status: APPROVED (owner 2026-10-08, «specs approved»; S1–S3 as recommended)
> Last Updated: 2026-10-08
> Requirements: `01-requirements.md` v0.3 (approved 2026-10-08)

## Overview

flutter_llama 1.2.0 adds the following, without breaking the 1.1.x API:

- a chat API that applies the model's own chat template;
- grammar / JSON-schema constrained output;
- tool calls;
- classification;
- token counting;
- capability and device-fit information;
- lifecycle handling;
- desktop Windows and Linux support.

All model logic moves into one shared C++ core, so the five platforms cannot drift apart. Today the same logic is
copied three times: `android/src/main/cpp/flutter_llama_bridge.cpp` (431 lines), and `ios/Classes/llama_cpp_bridge.mm`
plus `macos/Classes/llama_cpp_bridge.mm` (377 lines each, identical).

## Affected Systems

| Area | Change | Notes |
|---|---|---|
| `src/core/flutter_llama_core.{h,cpp}` (new) | Create | C ABI over llama.cpp: load, chat template, grammar sampling, stream callback, tokenize, model meta, label log-probs, embed, stop, unload |
| `android/src/main/cpp/flutter_llama_bridge.cpp` | Modify | Thin JNI wrapper over the core (the existing JNI names stay) |
| `android/.../FlutterLlamaPlugin.kt` | Modify | New channel methods; memory pressure (`onTrimMemory`) |
| `ios/Classes/llama_cpp_bridge.mm`, `macos/Classes/llama_cpp_bridge.mm` | Modify | Thin Objective-C++ wrappers over the core (one shared source for both) |
| `ios/.../FlutterLlamaPlugin.swift`, `macos/...` | Modify | New channel methods; memory warnings |
| `windows/`, `linux/` (new) | Create | FFI plugin (`ffiPlugin: true`): CMake builds the core plus the vendored llama.cpp (CPU, optional Vulkan; CUDA opt-in on Windows) |
| `lib/src/flutter_llama.dart` | Modify | New Dart API; routing (method channel on Android / iOS / macOS, FFI on Windows / Linux); `isSupported` |
| `lib/src/ffi/` (new) | Create | `dart:ffi` bindings to the core; streaming through `NativeCallable.listener` |
| `lib/src/models/` | Modify / Create | `LlamaMessage`, `ChatParams`, `ToolSpec`, `ToolCall`, `ChatResult`, `ChatChunk`, `ModelInfo`, `DeviceFit`, `ClassifyResult`, `LlamaError` |
| `lib/src/grammar/` (new) | Create | JSON schema → GBNF (Dart), tool-call grammar, label-choice grammar |
| `lib/src/models/preset_model.dart` | Modify | Open-licence presets only; licence fields; `ModelCatalog.register` for products |
| `example/`, `test/` | Modify | Chat-with-tools, classify and device-fit demos; unit tests with a fake platform / fake core; smoke tests per platform |
| `pubspec.yaml` | Modify | 1.2.0; platforms `windows` / `linux` (ffiPlugin); `ffi` dependency |

## Architecture

```
            Dart API (lib/src/flutter_llama.dart)
   chat / chatStream / classify / countTokens / modelInfo / canLoad / embed …
                 │                                        │
   MethodChannel (Android, iOS, macOS)            dart:ffi (Windows, Linux)
        │                    │                            │
  Kotlin + JNI       Swift + ObjC++                 *.so / *.dll
        └────────────────────┴──────────┬─────────────────┘
                                         ▼
                   src/core/flutter_llama_core (C ABI, C++)
                   └── vendored llama.cpp 945501f5e (MIT)
```

- **Why the method channels stay.** The owner's Android, iOS and macOS plugins and their GPU setups (Metal, Vulkan /
  OpenCL) work today. Extending them is lower risk than porting them.
- **Desktop uses FFI.** The FFI plugin template builds the CMake library per platform. The core is the same code, so
  behaviour is identical.
- **Streaming.** Native threads call a C callback with UTF-8 pieces. Channels deliver them through an `EventChannel`
  (as `generateStream` does today); FFI through `NativeCallable.listener`. Each loaded model has one generation lock
  and a cancel flag.

## Interfaces

### Dart (new, additive)

```dart
enum LlamaRole { system, user, assistant, tool }
class LlamaMessage { final LlamaRole role; final String content; final List<ToolCall> toolCalls; final String? toolCallId; final String? name; }
class ToolSpec { final String name; final String description; final Map<String, Object?> parameters; /* JSON schema */ }
class ToolCall { final String id; final String name; final Map<String, Object?> arguments; }

class ChatParams {            // + temperature, topP, topK, maxTokens, repeatPenalty, seed, stop (as GenerationParams)
  final List<ToolSpec> tools;
  final ToolChoice toolChoice;                  // auto | none | required | named(String)
  final String? grammar;                        // GBNF, wins over jsonSchema
  final Map<String, Object?>? jsonSchema;
  final ChatTemplate? template;                 // null = the model's own (GGUF tokenizer.chat_template)
  final bool thinking;                          // Qwen3-style reasoning on / off; default false
}

sealed class ChatChunk {}                       // chatStream: ChatText(text) | ChatToolCalls(calls) | ChatDone(reason, usage)
class ChatResult { final String text; final List<ToolCall> toolCalls; final ChatStopReason reason; final ChatUsage usage; }

class FlutterLlama {
  static bool get isSupported;                  // false on the web
  Future<ChatResult> chat(List<LlamaMessage> messages, [ChatParams params]);
  Stream<ChatChunk> chatStream(List<LlamaMessage> messages, [ChatParams params]);
  Future<ClassifyResult> classify(String text, List<String> labels, {ClassifyParams params});
  Future<int> countTokens(String text);
  Future<int> countChatTokens(List<LlamaMessage> messages, {ChatParams? params});
  Future<List<double>> embed(String text);      // should-have; embedding-capable models
  Future<ModelInfo?> modelInfo();               // getModelInfo() stays as the raw map
  Future<DeviceFit> canLoad(ModelRef model);    // a file or a preset: RAM / disk / platform
  LlamaLifecycle get lifecycle;                 // unloadOnBackground, idleTimeout, onMemoryPressure
  // 1.1.x unchanged: loadModel, generate, generateStream, stopGeneration, unloadModel, presets, downloaders
}

class ModelInfo {
  final String architecture;
  final int parameters;
  final String quantization;
  final int contextLength;
  final bool hasChatTemplate;
  final String? templateFamily;                 // chatml | llama3 | gemma | phi3 | mistral | granite | gpt2-plain | custom
  final bool nativeToolCalls;
  final int fileSize;
  final Map<String, String> gguf;               // general.* (name, license, languages, base model)
}
class DeviceFit { final bool ok; final int needBytes; final int availableBytes; final String? reason; } // too_large_ram | too_large_disk | unsupported_platform
class ClassifyResult { final String label; final Map<String, double> scores; final Duration took; }
sealed class LlamaError implements Exception {}  // UnsupportedPlatform, ModelNotLoaded, ModelTooLarge, GrammarInvalid, ContextOverflow, Cancelled, NativeFailure
```

### Tool calls (any instruction model)

1. **Native first.** If `ModelInfo.nativeToolCalls`, tools are rendered by the model's template (Qwen3, Granite,
   Llama-style). The output is parsed by that family's markers (`<tool_call>…</tool_call>` etc.).
2. **Grammar fallback (all models).**
   - The system message gets a compact tool list and "answer with exactly one JSON object".
   - Sampling is constrained to `{"tool": <name>, "arguments": <that tool's schema>} | {"answer": "<text>"}`.
   - The grammar is generated from the `ToolSpec` schemas in Dart.
3. **One repair retry** when parsing fails (for example a truncated stream). Then the call fails with
   `tool_parse_failed`, so the consumer can fall back.
4. `toolChoice: none` gives plain chat; `required` / `named` narrow the grammar.

### Classify

- **Default method.** A label-choice grammar plus per-label log-probabilities of the label tokens given
  `instructions + few-shot examples + text`, with softmax over the labels. The shared prompt prefix is evaluated once.
- **Alternative.** `ClassifyParams.method = embedding` (centroids of the examples) for embedding-capable models.
- **Target.** Under 50 ms for a ≤ 64-token text on a mid phone (Snapdragon 7-class / A15) with a 125M Q4 model, the
  model already loaded. The example app measures it. dropexpired's braindler is the reference case.

### Native core C ABI (`flutter_llama_core.h`)

```c
typedef struct fl_model fl_model;
typedef void (*fl_token_cb)(void* user, const char* piece, int len);
fl_model* fl_load(const char* path, const fl_load_params* p, char* err, int err_len);
int  fl_apply_chat_template(fl_model*, const fl_message* msgs, int n, const char* tmpl_override, int add_assistant, char* out, int out_len);
int  fl_generate(fl_model*, const char* prompt, const fl_sample_params* sp, const char* gbnf, fl_token_cb cb, void* user, fl_usage* usage);
int  fl_tokenize_count(fl_model*, const char* text, int add_special);
int  fl_meta(fl_model*, const char* key, char* out, int out_len);
int  fl_label_logprobs(fl_model*, const char* prompt, const char** labels, int n, float* out);
int  fl_embed(fl_model*, const char* text, float* out, int dim);
void fl_stop(fl_model*);
void fl_free(fl_model*);
```

- **Templates.** Built-in families go through `llama_chat_apply_template`. GGUF Jinja templates go through llama.cpp
  `common/chat` when it can render them; otherwise a Dart-side family template is used.
- **Grammar.** `llama_sampler_init_grammar`. **Meta:** `llama_model_meta_val_str`.

### Presets and catalogue (open models only)

```dart
class PresetModel {               // existing fields + …
  final String license;           // SPDX: Apache-2.0 | MIT
  final String? baseModel;
  final int ramBytes;
  final int downloadBytes;
  final List<String> languages;   // BCP-47
  final bool goodAtTools;
  final Set<LlamaTask> tasks;     // chat, tools, classify, embed
}
class ModelCatalog { static List<PresetModel> builtIn; static void register(PresetModel preset); }  // products add theirs
```

**Built-in presets** (GGUF Q4_K_M; licence verified from the model card at release):

| Preset | Licence | ~Download | Use |
|---|---|---|---|
| Qwen3-0.6B | Apache-2.0 | 0.4 GB | low-end phones, chat |
| Qwen3-1.7B | Apache-2.0 | 1.1 GB | phones: chat + tools (default mobile) |
| Qwen3-4B | Apache-2.0 | 2.5 GB | high-end phones, 8 GB Macs, CPU desktops |
| Qwen3-8B | Apache-2.0 | 5 GB | Apple Silicon ≥ 16 GB, GPUs ≥ 8 GB VRAM |
| Granite 3.x 2B / 8B Instruct | Apache-2.0 | 1.5 / 5 GB | tool-calling alternative |
| Phi-4-mini | MIT | 2.4 GB | English-centric alternative |
| SmolLM2-360M | Apache-2.0 | 0.3 GB | tiny chat / classify |

`nativemind/braindler` and `nativemind/shridhar_8k_multimodal` leave the built-in list:

- braindler becomes dropexpired's product preset (`ModelCatalog.register` in dropexpired);
- shridhar goes to its own product.

Both stay loadable as any GGUF.

## Behavior

- **Routing.** `kIsWeb` → `UnsupportedPlatform`. Android, iOS and macOS use the channel backend; Windows and Linux use
  the FFI backend. `dart:ffi` sits behind conditional imports, so web builds still compile.
- **Memory.**
  - `canLoad` uses the preset `ramBytes`, or the file size × 1.2 + the KV cache for the context, against available
    memory:
    - Android: `ActivityManager.MemoryInfo`;
    - iOS: `os_proc_available_memory`;
    - macOS / Linux / Windows: `sysctl`, `/proc/meminfo`, `GlobalMemoryStatusEx`.
  - A memory warning stops generation and unloads the model (default `onMemoryPressure: unload`). The next call
    reloads it.
- **Background / idle.**
  - `unloadOnBackground`: true on mobile, false on desktop.
  - Idle timeout: 5 min on mobile, off on desktop.
- **Concurrency.** One generation per loaded model; further calls queue.
- **Cancellation.** `stop()` sets a flag checked per token. The stream ends with `ChatDone(reason: cancelled)`; the KV
  cache stays valid.

## Edge Cases

| Case | Behaviour |
|---|---|
| GGUF without a chat template | Family template by architecture (gpt2 → plain `User:/Assistant:` as in braindler's Ollama template) or the caller's `template` |
| Jinja template that llama.cpp cannot render | Family template; `templateFamily = custom`, debug warning |
| Invalid schema / grammar | `GrammarInvalid` before generation |
| Prompt longer than the context | `ContextOverflow` with the counts; consumers trim with `countChatTokens` |
| Model not good at tools | `goodAtTools == false` → consumers go answer-only; the grammar still guarantees parseable output |
| Windows / Linux without a GPU | CPU path; `ModelInfo` reports the backend |
| No licence in the GGUF metadata | Presets carry theirs; user files show "unknown" |

## Dependencies

- Vendored llama.cpp `945501f5e` (MIT). Its bundled `llama.h` already has the template, grammar sampler, tokenizer,
  meta and embedding APIs.
- Dart `ffi` ^2. Flutter ≥ 3.24 (`NativeCallable.listener`).
- Desktop: CMake ≥ 3.14; MSVC 2022 on Windows; GCC / Clang on Linux; Vulkan SDK optional.

## Testing Strategy

- **Dart unit tests** (no native code; the existing 70 stay green):
  - message → payload mapping;
  - JSON schema → GBNF (types, enums, nesting, arrays, required);
  - tool-call parsing / repair and family markers;
  - classify scoring;
  - routing and errors;
  - `canLoad` arithmetic;
  - lifecycle timers (fake clock).
- **Core ctest** on desktop with a tiny Apache-2.0 GGUF (SmolLM2-135M Q4): template, grammar output parses, token
  count, label log-probs.
- **Example smoke tests** (chat + tool call + classify on the tiny model): Android emulator, iOS simulator, macOS,
  Windows, Linux.

## Open Questions (spec level)

- [x] **S1: bridge strategy.** (approved with the spec, recommendation taken) Recommended: one C++ core, the existing channel plugins on Android / iOS / macOS, FFI
  on Windows / Linux. The alternative is FFI on all five, which rewrites the owner's working mobile plugins.
- [x] **S2: where desktop and Apple builds are tested.** (approved with the spec, recommendation taken) Recommended, with no paid CI:
  - macOS and iOS on the owner's MacBook M4;
  - Linux on this server;
  - Windows on a Windows machine the owner provides.
- [x] **S3: llama.cpp version.** (approved with the spec, recommendation taken) Recommended: stay on `945501f5e` unless a needed API is missing; an upgrade is its
  own task.
