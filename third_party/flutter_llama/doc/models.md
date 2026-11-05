# Models

flutter_llama 1.2 includes **open models only** among its built-in presets: weights under Apache-2.0 or MIT. Each
licence was verified from the model card on 2026-10-08. The package itself is licensed under NativeMindNONC. Any
other GGUF file loads too (`loadModel(LlamaConfig(modelPath: …))`). Products add their own presets with
`ModelCatalog.register`.

## Built-in presets (`ModelCatalog.builtIn`)

All presets are GGUF Q4_K_M from Hugging Face. **RAM** is the load at the preset's context: weights plus KV cache.

| Preset | Licence | Download | RAM | Context | Tools | Use |
|---|---|---|---|---|---|---|
| `OpenModels.qwen3_0_6b` | Apache-2.0 ([card](https://huggingface.co/Qwen/Qwen3-0.6B)) | 0.4 GB | 0.9 GB | 4096 | yes | Low-end phones; chat and simple tools |
| `OpenModels.qwen3_1_7b` | Apache-2.0 ([card](https://huggingface.co/Qwen/Qwen3-1.7B)) | 1.1 GB | 1.9 GB | 4096 | yes | **Default on phones**: chat, tools, classify |
| `OpenModels.qwen3_4b` | Apache-2.0 ([card](https://huggingface.co/Qwen/Qwen3-4B)) | 2.5 GB | 4 GB | 8192 | yes | High-end phones, 8 GB Macs, CPU desktops |
| `OpenModels.qwen3_8b` | Apache-2.0 ([card](https://huggingface.co/Qwen/Qwen3-8B)) | 5 GB | 7 GB | 8192 | yes | Apple Silicon ≥ 16 GB, GPUs ≥ 8 GB VRAM |
| `OpenModels.granite3_3_2b` | Apache-2.0 ([card](https://huggingface.co/ibm-granite/granite-3.3-2b-instruct)) | 1.5 GB | 2.6 GB | 8192 | yes | Tool-calling alternative for phones |
| `OpenModels.granite3_3_8b` | Apache-2.0 ([card](https://huggingface.co/ibm-granite/granite-3.3-8b-instruct)) | 4.9 GB | 7 GB | 8192 | yes | Tool-calling alternative for desktops |
| `OpenModels.phi4Mini` | MIT ([card](https://huggingface.co/microsoft/Phi-4-mini-instruct)) | 2.5 GB | 4 GB | 8192 | — | English-centric chat and classify |
| `OpenModels.smolLm2_360m` | Apache-2.0 ([card](https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct)) | 0.3 GB | 0.6 GB | 4096 | — | Tiny English chat and classify |

Before offering a download, call `canLoad(ModelRef.download(bytes: p.downloadBytes!, directory: …, ramBytes:
p.ramBytes))`. It checks free disk and available memory.

## Per platform

| Platform | Recommended | Notes |
|---|---|---|
| Android, mid-range (6–8 GB) | Qwen3 1.7B | Qwen3 0.6B on 4 GB phones. Background unload and the 5-minute idle timeout are on by default |
| iOS (A15+, 6 GB) | Qwen3 1.7B | Qwen3 4B on 8 GB devices (Pro models) |
| macOS (Apple Silicon) | Qwen3 4B on 8 GB; Qwen3 8B on ≥ 16 GB | Metal; the fastest desktop path |
| Windows / Linux, CPU only | Qwen3 4B | Qwen3 1.7B on older CPUs. Default threads: half the logical cores, at most 8 |
| Windows / Linux, GPU ≥ 8 GB | Qwen3 8B | Vulkan (`FLUTTER_LLAMA_VULKAN`) or CUDA on Windows (`FLUTTER_LLAMA_CUDA`) |
| Web | none | `FlutterLlama.isSupported == false`; use a server engine |

## Tool calls

- **Native.** Qwen3 renders tools in its own template (`<tool_call>`), and `ChatParams.tools` uses that path.
- **Grammar.** Every other instruction model gets a grammar-constrained JSON reply, which parses by construction.
- **Tested.** Qwen3-0.6B made two calls in one reply and then answered (Linux, 2026-10-08).
- **Model choice.** Prefer `goodAtTools` presets for agents.

## Classification

- `classify` scores each label by its log-probability.
- **Small models.** Models of 1B parameters or less lean towards catch-all labels ("unknown", "other"). Drop such
  labels, or use a fine-tuned classifier registered as a product preset (dropexpired's braindler).

## Product presets

```dart
ModelCatalog.register(const PresetModel(
  id: 'nativemind/braindler', name: 'Braindler classifier', description: '…',
  source: ModelSource.ollama, variant: 'q4_k_s', size: '88 MB', tasks: {LlamaTask.classify},
));
```

The 1.1 `PresetModels` (braindler, shridhar) are kept for compatibility. They are not part of the built-in
catalogue.
