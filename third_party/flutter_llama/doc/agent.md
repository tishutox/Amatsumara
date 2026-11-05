# The agent API (flutter_llama 1.2)

Chat with tools, classification, device fit and the open-model catalogue, on Android, iOS, macOS, Linux and Windows.
Model choice per platform and task: [`models.md`](models.md). A runnable tour: the example app's robot button
(`example/lib/agent/agent_screen.dart`).

**Open models only.** The built-in presets (`ModelCatalog.builtIn`, `OpenModels.*`) are Apache-2.0 or MIT, each with
its licence in `PresetModel.license`. Other weights can be added with `ModelCatalog.register`, and their licence is
then the app's responsibility.

## Load

```dart
final llama = FlutterLlama.instance;
final fit = await llama.canLoad(ModelRef.download(bytes: OpenModels.qwen3_1_7b.downloadBytes!, directory: dir.path,
    ramBytes: OpenModels.qwen3_1_7b.ramBytes));
if (fit.ok) {
  await llama.loadPresetModel(preset: OpenModels.qwen3_1_7b, onProgress: (p) => print(p.progress));
}
```

- `canLoad` checks memory and disk before anything is downloaded. For a GGUF on disk (`ModelRef.file`) it reads the
  file header to size the KV cache. `reason` is one of `too_large_ram`, `too_large_disk`, `unsupported_platform` or
  `unknown_memory`.
- **GPU (Android).** `LlamaConfig(nGpuLayers: -1)` means auto: layers go to the Vulkan GPU only where it beats the CPU.
  On a Mali-G57, ggml-vulkan was about 3× slower than the CPU (2.0 vs 6.5–7.3 tok/s, Qwen3-0.6B), so Mali and PowerVR
  stay on the CPU, and Adreno and others get every layer. A number ≥ 0 is used as given.
  - `getModelInfo()['backends']` lists what loaded, e.g. `CPU (CPU);Vulkan0 (Mali-G57 MC2)`.
  - The CPU and Vulkan backends are separate modules loaded at run time, so minSdk stays 24.
- **Lifecycle.** `LlamaLifecycle` unloads the model when the app goes to the background (mobile default) or after an
  idle timeout, and on memory pressure.

## Chat and tools

```dart
const clock = ToolSpec(name: 'utc_now', description: 'The current time in UTC', parameters: {'type': 'object', 'properties': {}});
var r = await llama.chat(messages, const ChatParams(tools: [clock]));
while (r.toolCalls.isNotEmpty) {
  messages.add(LlamaMessage(LlamaRole.assistant, r.text, toolCalls: r.toolCalls));
  for (final c in r.toolCalls) {
    messages.add(LlamaMessage(LlamaRole.tool, jsonEncode(run(c)), toolCallId: c.id, name: c.name));
  }
  r = await llama.chat(messages, const ChatParams(tools: [clock]));
}
```

- **Templates.** The model's own chat template comes from its GGUF; override it with `ChatParams(template:)`.
- **Tool calls** are constrained by a grammar built from the tool specs, so a call always parses.
  - `toolChoice` is `auto`, `none`, `required` or a named tool.
  - Models with `goodAtTools` are the reliable ones.
- **Structured output:** `ChatParams(jsonSchema:)` or a raw GBNF `grammar:`.
- **Streaming:** `chatStream` yields `ChatText`, `ChatToolCalls` and a final `ChatDone(reason, usage)`.
- **Reasoning** on or off: `thinking` (Qwen3 `/think` / `/no_think`). Reasoning text is filtered out of `text`.
- `countTokens` / `countChatTokens` measure a prompt before sending it.

## Classify

```dart
final r = await llama.classify('The auction is next month', ['urgent', 'routine', 'spam']);
// r.label, r.scores (probabilities summing to 1), r.took
```

- `ClassifyMethod.logprob` (default) scores each label's log-probability, so the answer is always one of the
  labels. `examples` give few-shot texts per label.
- `ClassifyMethod.embedding` compares `embed()` vectors with the examples' centroids.

## Desktop

| Platform | State |
|---|---|
| Linux | Same Dart API through FFI onto the shared core (`src/core`, `linux/`) |
| Windows | Code is ready (`windows/`); waits for a Windows build machine |
| macOS / iOS | The Swift bridge |

Recommended models per OS are in `models.md`.

## From 1.1

- **Unchanged:** `loadModel`, `generate`, `generateStream`, `getModelInfo` and `stopGeneration`. `compat_api_test`
  keeps them.
- **Use instead of 1.1 code:** `chat` / `chatStream` instead of hand-built prompts; `canLoad` before downloading;
  `ModelCatalog` / `OpenModels` instead of the 1.1 `PresetModels`.
- The 1.1 presets `braindler` and `shridhar` still exist but are not in `builtIn`. Removal is proposed for 2.0.
- **Android release builds** now ship consumer R8 rules (`android/consumer-rules.pro`). Before them, R8 stripped the
  JNI result classes, and the first `getModelInfo` crashed with `NoSuchMethodError`.
