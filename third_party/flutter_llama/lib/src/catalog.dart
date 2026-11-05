/// The model catalogue (sdd-flutter-llama-agent 4.1): built-in open-model presets (Apache-2.0 or MIT, verified from
/// each model card) plus presets products register.
library;

import 'models/model_source.dart';
import 'models/preset_model.dart';

const _mb = 1 << 20;

/// Built-in open models (GGUF Q4_K_M; `downloadBytes` exact as of 2026-10-08; `files` is the file to download from the Hugging Face repo `id`).
abstract final class OpenModels {
  static const qwen3_0_6b = PresetModel(
    id: 'unsloth/Qwen3-0.6B-GGUF',
    name: 'Qwen3 0.6B',
    description: 'Low-end phones: chat and simple tools; 100+ languages.',
    source: ModelSource.huggingFace,
    files: ['Qwen3-0.6B-Q4_K_M.gguf'],
    languages: ['multilingual'],
    size: '0.4 GB',
    contextSize: 4096,
    license: 'Apache-2.0',
    baseModel: 'Qwen/Qwen3-0.6B',
    downloadBytes: 396705472,
    ramBytes: 900 * _mb,
    goodAtTools: true,
    tasks: {LlamaTask.chat, LlamaTask.tools},
    cardUrl: 'https://huggingface.co/Qwen/Qwen3-0.6B',
  );

  static const qwen3_1_7b = PresetModel(
    id: 'unsloth/Qwen3-1.7B-GGUF',
    name: 'Qwen3 1.7B',
    description: 'The default on phones: chat and tools; 100+ languages.',
    source: ModelSource.huggingFace,
    files: ['Qwen3-1.7B-Q4_K_M.gguf'],
    languages: ['multilingual'],
    size: '1.1 GB',
    contextSize: 4096,
    license: 'Apache-2.0',
    baseModel: 'Qwen/Qwen3-1.7B',
    downloadBytes: 1107409472,
    ramBytes: 1900 * _mb,
    goodAtTools: true,
    tasks: {LlamaTask.chat, LlamaTask.tools, LlamaTask.classify},
    cardUrl: 'https://huggingface.co/Qwen/Qwen3-1.7B',
  );

  static const qwen3_4b = PresetModel(
    id: 'Qwen/Qwen3-4B-GGUF',
    name: 'Qwen3 4B',
    description: 'High-end phones, 8 GB Macs, CPU desktops.',
    source: ModelSource.huggingFace,
    files: ['Qwen3-4B-Q4_K_M.gguf'],
    languages: ['multilingual'],
    size: '2.5 GB',
    contextSize: 8192,
    license: 'Apache-2.0',
    baseModel: 'Qwen/Qwen3-4B',
    downloadBytes: 2497280256,
    ramBytes: 4000 * _mb,
    goodAtTools: true,
    tasks: {LlamaTask.chat, LlamaTask.tools, LlamaTask.classify},
    cardUrl: 'https://huggingface.co/Qwen/Qwen3-4B',
  );

  static const qwen3_8b = PresetModel(
    id: 'Qwen/Qwen3-8B-GGUF',
    name: 'Qwen3 8B',
    description: 'Apple Silicon with 16 GB or more, GPUs with 8 GB of VRAM.',
    source: ModelSource.huggingFace,
    files: ['Qwen3-8B-Q4_K_M.gguf'],
    languages: ['multilingual'],
    size: '5 GB',
    contextSize: 8192,
    license: 'Apache-2.0',
    baseModel: 'Qwen/Qwen3-8B',
    downloadBytes: 5027783488,
    ramBytes: 7000 * _mb,
    goodAtTools: true,
    tasks: {LlamaTask.chat, LlamaTask.tools, LlamaTask.classify},
    cardUrl: 'https://huggingface.co/Qwen/Qwen3-8B',
  );

  static const granite3_3_2b = PresetModel(
    id: 'ibm-granite/granite-3.3-2b-instruct-GGUF',
    name: 'Granite 3.3 2B Instruct',
    description: 'A tool-calling alternative for phones (IBM).',
    source: ModelSource.huggingFace,
    files: ['granite-3.3-2b-instruct-Q4_K_M.gguf'],
    languages: ['en', 'de', 'es', 'fr', 'ja', 'pt', 'ar', 'cs', 'it', 'ko', 'nl', 'zh'],
    size: '1.5 GB',
    contextSize: 8192,
    license: 'Apache-2.0',
    baseModel: 'ibm-granite/granite-3.3-2b-instruct',
    downloadBytes: 1545303328,
    ramBytes: 2600 * _mb,
    goodAtTools: true,
    tasks: {LlamaTask.chat, LlamaTask.tools},
    cardUrl: 'https://huggingface.co/ibm-granite/granite-3.3-2b-instruct',
  );

  static const granite3_3_8b = PresetModel(
    id: 'ibm-granite/granite-3.3-8b-instruct-GGUF',
    name: 'Granite 3.3 8B Instruct',
    description: 'A tool-calling alternative for desktops (IBM).',
    source: ModelSource.huggingFace,
    files: ['granite-3.3-8b-instruct-Q4_K_M.gguf'],
    languages: ['en', 'de', 'es', 'fr', 'ja', 'pt', 'ar', 'cs', 'it', 'ko', 'nl', 'zh'],
    size: '4.9 GB',
    contextSize: 8192,
    license: 'Apache-2.0',
    baseModel: 'ibm-granite/granite-3.3-8b-instruct',
    downloadBytes: 4942873344,
    ramBytes: 7000 * _mb,
    goodAtTools: true,
    tasks: {LlamaTask.chat, LlamaTask.tools},
    cardUrl: 'https://huggingface.co/ibm-granite/granite-3.3-8b-instruct',
  );

  static const phi4Mini = PresetModel(
    id: 'unsloth/Phi-4-mini-instruct-GGUF',
    name: 'Phi-4-mini Instruct',
    description: 'An English-centric alternative (Microsoft).',
    source: ModelSource.huggingFace,
    files: ['Phi-4-mini-instruct-Q4_K_M.gguf'],
    languages: ['en'],
    size: '2.5 GB',
    contextSize: 8192,
    license: 'MIT',
    baseModel: 'microsoft/Phi-4-mini-instruct',
    downloadBytes: 2491874272,
    ramBytes: 4000 * _mb,
    tasks: {LlamaTask.chat, LlamaTask.classify},
    cardUrl: 'https://huggingface.co/microsoft/Phi-4-mini-instruct',
  );

  static const smolLm2_360m = PresetModel(
    id: 'bartowski/SmolLM2-360M-Instruct-GGUF',
    name: 'SmolLM2 360M Instruct',
    description: 'Tiny English chat and classification.',
    source: ModelSource.huggingFace,
    files: ['SmolLM2-360M-Instruct-Q4_K_M.gguf'],
    languages: ['en'],
    size: '0.3 GB',
    contextSize: 4096,
    license: 'Apache-2.0',
    baseModel: 'HuggingFaceTB/SmolLM2-360M-Instruct',
    downloadBytes: 270590880,
    ramBytes: 600 * _mb,
    tasks: {LlamaTask.chat, LlamaTask.classify},
    cardUrl: 'https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct',
  );
}

/// The built-in presets plus those registered by products.
abstract final class ModelCatalog {
  /// Open models only (Apache-2.0 / MIT).
  static const List<PresetModel> builtIn = [
    OpenModels.qwen3_0_6b,
    OpenModels.qwen3_1_7b,
    OpenModels.qwen3_4b,
    OpenModels.qwen3_8b,
    OpenModels.granite3_3_2b,
    OpenModels.granite3_3_8b,
    OpenModels.phi4Mini,
    OpenModels.smolLm2_360m,
  ];

  static final List<PresetModel> _registered = [];

  /// Adds a product preset (e.g. a fine-tuned classifier); a preset with the same id and file replaces the earlier one.
  static void register(PresetModel preset) {
    _registered.removeWhere((p) => p.id == preset.id && _file(p) == _file(preset));
    _registered.add(preset);
  }

  static String? _file(PresetModel p) => p.files.isEmpty ? p.variant : p.files.first;

  /// Built-in first, then registered.
  static List<PresetModel> get all => [...builtIn, ..._registered];

  /// Presets good for [task].
  static List<PresetModel> forTask(LlamaTask task) => [for (final p in all) if (p.tasks.contains(task)) p];

  /// Clears registered presets (tests).
  static void debugReset() => _registered.clear();
}
