# Requirements: flutter_llama for agents (chat, tools, capabilities)

> Version: 0.2
> Status: APPROVED (owner 2026-10-08, «reqs approved по обоим», v0.3)
> Changes 0.2 (owner 2026-10-08):
> - F3: only open models in the flutter_llama build, and the package itself under NativeMindNONC;
> - F4: desktop Windows, Linux and macOS are in this flow.
> Changes 0.3 (owner 2026-10-08: «сверхлёгкий офлайн-классификатор нужен для dropexpired»): item 13, classification
> with tiny models; `nativemind/braindler` (GPT-2, 125M, Q4_K_M ≈ 94 MB) becomes dropexpired's offline classifier.
> Last Updated: 2026-10-08
> Origin: owner 2026-10-08 — flutter_llama is the universal on-device LLM tool; extend it (not its consumers) for what
> `nativemind_copilot` needs (`widgets.nativemind.net/flows/sdd-nativemind-copilot`, item 15).

## Problem Statement

`flutter_llama` runs GGUF models on Android, iOS and macOS, but only as "prompt in, text out". An agent needs:

- conversations formatted with the model's own chat template;
- reliable tool calls;
- token budgets;
- knowledge of what the model and the device can do.

Doing this in every consumer duplicates fragile logic (templates differ per model family) and loses the native
features that llama.cpp already ships (template application, grammar-constrained sampling, tokenizer).

## User Stories

### Primary

**As** an app developer using `flutter_llama` (e.g. `nativemind_copilot`)
**I want** to send a list of role messages (system / user / assistant / tool) and get the reply streamed
**So that** I never hand-write a model's chat template.

**As** an agent library
**I want** the model's output constrained to a JSON schema or grammar when it calls a tool
**So that** small on-device models produce parseable tool calls.

**As** an app developer
**I want** to know before loading whether a model fits this device and what it supports (context length, chat
template, tools, languages, licence)
**So that** I can choose a model and explain the choice to the user.

### Secondary

- As a developer, I want token counts for text and messages, so that I can keep within the context window and trim
  history.
- As a developer, I want the model to unload on memory pressure / background, and an idle timeout, so that the app
  is not killed by the OS.
- As a developer, I want a clear "unsupported platform" answer on web / Linux / Windows (no crash, no missing-plugin
  exception), so that consumers can fall back to a cloud model.

## Acceptance Criteria

### Must Have

1. **Chat API.**
   - **Given** a loaded model with a chat template in its GGUF metadata, **when** I call
     `chat(messages, params)` / `chatStream(...)`, **then** the native side applies the model's template
     (`llama_chat_apply_template`, with an add-assistant prefix) and streams the reply.
   - A template override (named family or a Jinja-like string) is possible.
   - The template's stop / end-of-turn tokens end the reply.
2. **Structured output.**
   - **Given** a GBNF grammar or a JSON schema (converted to GBNF), **when** generating, **then** sampling is
     grammar-constrained and the result parses.
   - The same works in streaming mode.
3. **Tool-call helper.**
   - **Given** tool definitions (name, description, JSON-schema parameters), **when** I call `chat` with tools,
     **then** I get either text or `toolCalls: [{name, arguments}]`. Tool results are passed back as `tool`
     messages.
   - Works on any instruction model through the grammar. Native tool-call templates are used when the model has
     them.
4. **Tokens.** `countTokens(text)` and `countChatTokens(messages)` use the loaded model's tokenizer. Context length
   and the remaining budget come from model info.
5. **Model info and capabilities.**
   - `getModelInfo()` returns: architecture, parameters, quantisation, context length, chat template present /
     family, file size, and the GGUF general metadata (name, licence, languages when present).
   - A preset catalogue entry carries: RAM needed, download size, "good at tools" and languages.
6. **Device fit.**
   - `canLoad(model)` checks available RAM / storage against the model's needs, with a reason.
   - Loading a model that does not fit fails with a typed error, not a crash.
7. **Lifecycle.** Unload on memory warnings (iOS / Android), an optional unload on app background, an idle timeout,
   and a cancel / stop that leaves the context usable.
8. **Desktop** (owner F4): Windows (x64; CPU + Vulkan, CUDA optional) and Linux (x64 / arm64; CPU + Vulkan) join
   Android, iOS and macOS. Every feature of this flow works on all five platforms.
9. **Unsupported platforms.**
   - `FlutterLlama.isSupported` is false on the web only.
   - Every call there throws a typed `UnsupportedPlatform` error.
   - Importing the package never breaks a web build.
10. **Compatibility.** The existing API (`generate`, `generateStream`, presets, downloaders) keeps working (semver
   minor bump).
11. **Tests.** Dart unit tests with a fake platform: messages → channel payloads, schema → GBNF, tool-call parsing.
    Native smoke tests on a tiny GGUF in the example app (Android emulator, iOS simulator, macOS, Windows, Linux).
12. **Open models only** (owner F3): every preset or bundled model in the package has an open licence (Apache-2.0 / MIT
    class, verified from the model card at release). Models under custom community / research licences (e.g. Llama
    Community, Gemma terms, Qwen research) are not presets; users can still load any GGUF they choose. The current presets
    (`nativemind/braindler` Q2_K…F16, `nativemind/shridhar_8k_multimodal`; both GPT-2 125M, MIT-licensed base) are checked the same way: their own licence
    and the licence of the base model they were tuned from. A preset that fails the check is removed or replaced.
13. **Classification** (owner 2026-10-08, for dropexpired's ultra-light offline classifier).
    - `classify(text, labels, {examples, instructions})` returns the best label and a score per label. Tiny models
      such as `nativemind/braindler` (GPT-2, 125M) are enough.
    - Implementation: grammar-constrained choice among the labels, scored by token log-probabilities; or embeddings
      plus nearest label examples when the model is better at that. Both must run offline on every platform.
    - Latency target: tens of milliseconds per short text on a mid phone after the model is loaded. Footprint under
      about 100 MB.
    - Models and their labels belong to the product. dropexpired ships braindler and its intent labels; the plugin
      provides the mechanism.

### Should Have

- Multi-session: several conversations reuse the loaded model with separate KV caches, or with prompt caching of the
  system prefix.
- Embeddings (`embed(text)`) for local retrieval.
- A progress callback for the first load (mmap / warm-up), and a time-to-first-token metric.

### Won't Have (This Iteration)

- Training, fine-tuning, LoRA management.
- A web (WASM) backend.
- Multimodal (image) input. It was removed earlier without a native implementation; a later flow can bring it back.

## Constraints

- **Code:** the owner's code and API are the base: extend, don't rewrite. Vendored llama.cpp `945501f5e`; upgrading
  it is allowed only when a needed API is missing, and that is its own task.
- **Platforms:** Android (JNI), iOS and macOS (Objective-C++ bridge + xcframework), Windows and Linux (new desktop bridges; plugin or FFI is a spec decision). Every bridge gets every feature.
- **Package size:** keep `.pubignore` discipline (v1.1.2 optimised the size).
- **Licence:** the package is NativeMindNONC (owner F3); llama.cpp stays MIT inside it; presets only open-licence models.
- **Git:** the owner's; no git writes.

## Open Questions

- [ ] **F1: chat API shape.** Recommended: `chat(List<LlamaMessage>, ChatParams)` and `chatStream(...)` next to the
  existing `generate*`, with `LlamaMessage(role, content, toolCalls?, toolCallId?)`. Alternatively an OpenAI-
  compatible map API.
- [ ] **F2: JSON schema → GBNF.** Recommended: in Dart (portable, testable) and sent to the native grammar sampler.
  The alternative is the llama.cpp `json-schema-to-grammar` C++ code in both bridges.
- [x] **F3 → open models only; the package under NativeMindNONC** (owner 2026-10-08). Earlier recommendation:
  **default presets for agents.** Recommended: small instruction models with good tool following and Q4_K_M
  GGUF: Qwen2.5 1.5B / 3B Instruct, Llama 3.2 3B Instruct; Gemma 2 2B for text only. Licences to be checked.
- [x] **F4 → desktop Windows / Linux / macOS in this flow; web stays out** (owner 2026-10-08). Earlier text:
  **other platforms.** Recommended: out of this iteration (typed "unsupported"). A later flow decides on
  Linux / Windows (desktop llama.cpp is easy) and on web (WASM, heavy).
- [ ] **F5: version.** Recommended: 1.2.0 (additive), published to pub.dev on the owner's command.

## References

- Consumer requirements: `widgets.nativemind.net/flows/sdd-nativemind-copilot/01-requirements.md` items 15–16, L1–L6.
- Code:
  - `lib/src/flutter_llama.dart`
  - `lib/src/models/generation_params.dart`
  - `android/src/main/cpp/flutter_llama_bridge.cpp`
  - `android/src/main/kotlin/net/nativemind/flutter_llama/FlutterLlamaPlugin.kt`
  - `ios/Classes/llama_cpp_bridge.mm`
  - `ios/llama.xcframework/*/llama.framework/Headers/llama.h`

## Approval

- [x] Reviewed by: owner
- [x] Approved on: 2026-10-08 (v0.3)
