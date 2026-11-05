import 'model_source.dart';

/// What a model is good for (1.2 catalogue).
enum LlamaTask { chat, tools, classify, embed }

/// Информация о предустановленной модели
class PresetModel {
  final String id;
  final String name;
  final String description;
  final ModelSource source;
  final String? variant; // Для Ollama (q2_k, q4_k_s и т.д.)
  final List<String> files;
  final List<String> languages;
  final String size;
  final int? contextSize;
  final Map<String, dynamic>? metadata;

  /// SPDX licence of the weights (1.2: built-in presets are Apache-2.0 or MIT only).
  final String? license;

  /// The model this one is a quantisation or fine-tune of.
  final String? baseModel;

  /// Memory a load needs at [contextSize] (weights + KV cache), when known.
  final int? ramBytes;

  /// Download size in bytes, when known.
  final int? downloadBytes;

  /// Reliable at tool calls.
  final bool goodAtTools;

  /// What the model is meant for.
  final Set<LlamaTask> tasks;

  /// Where the licence was verified (the model card).
  final String? cardUrl;

  const PresetModel({
    required this.id,
    required this.name,
    required this.description,
    required this.source,
    this.variant,
    this.files = const [],
    this.languages = const [],
    required this.size,
    this.contextSize,
    this.metadata,
    this.license,
    this.baseModel,
    this.ramBytes,
    this.downloadBytes,
    this.goodAtTools = false,
    this.tasks = const {LlamaTask.chat},
    this.cardUrl,
  });
  
  /// Полное имя модели с вариантом
  String get fullName {
    if (variant != null) {
      return '$id:$variant';
    }
    return id;
  }
  
  /// Копирование с изменениями
  PresetModel copyWith({
    String? id,
    String? name,
    String? description,
    ModelSource? source,
    String? variant,
    List<String>? files,
    List<String>? languages,
    String? size,
    int? contextSize,
    Map<String, dynamic>? metadata,
    String? license,
    String? baseModel,
    int? ramBytes,
    int? downloadBytes,
    bool? goodAtTools,
    Set<LlamaTask>? tasks,
    String? cardUrl,
  }) {
    return PresetModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      source: source ?? this.source,
      variant: variant ?? this.variant,
      files: files ?? this.files,
      languages: languages ?? this.languages,
      size: size ?? this.size,
      contextSize: contextSize ?? this.contextSize,
      metadata: metadata ?? this.metadata,
      license: license ?? this.license,
      baseModel: baseModel ?? this.baseModel,
      ramBytes: ramBytes ?? this.ramBytes,
      downloadBytes: downloadBytes ?? this.downloadBytes,
      goodAtTools: goodAtTools ?? this.goodAtTools,
      tasks: tasks ?? this.tasks,
      cardUrl: cardUrl ?? this.cardUrl,
    );
  }
  
  @override
  String toString() {
    return 'PresetModel($fullName, source: ${source.displayName}, size: $size)';
  }
}

/// Список предустановленных моделей
///
/// 1.1 presets, kept for compatibility. Since 1.2 the built-in list is [ModelCatalog] (open models only); braindler
/// and shridhar are product presets their products register with `ModelCatalog.register`.
class PresetModels {
  // HuggingFace модели
  static const shridharMultimodal = PresetModel(
    id: 'nativemind/shridhar_8k_multimodal',
    name: 'Shridhar 8K Multimodal',
    description: 'Мультимодальная духовная модель с поддержкой 4 языков',
    source: ModelSource.huggingFace,
    files: [
      'adapter_model.safetensors',
      'adapter_config.json',
    ],
    languages: ['🇷🇺 Русский', '🇪🇸 Испанский', '🇮🇳 Хинди', '🇹🇭 Тайский'],
    size: '~50 MB',
    contextSize: 8192,
  );
  
  // Ollama модели - Braindler
  static const braindlerQ2K = PresetModel(
    id: 'nativemind/braindler',
    name: 'Braindler Q2_K',
    description: 'Самая быстрая версия, оптимальна для мобильных устройств',
    source: ModelSource.ollama,
    variant: 'q2_k',
    files: [],
    languages: ['🇬🇧 English'],
    size: '72 MB',
    contextSize: 2048,
    metadata: {
      'recommended': false,
      'speed': 'fastest',
    },
  );
  
  static const braindlerQ4K = PresetModel(
    id: 'nativemind/braindler',
    name: 'Braindler Q4_K',
    description: '⭐ Рекомендуется - оптимальный баланс скорости и качества',
    source: ModelSource.ollama,
    variant: 'q4_k_s',
    files: [],
    languages: ['🇬🇧 English'],
    size: '88 MB',
    contextSize: 2048,
    metadata: {
      'recommended': true,
      'speed': 'fast',
    },
  );
  
  static const braindlerQ5K = PresetModel(
    id: 'nativemind/braindler',
    name: 'Braindler Q5_K',
    description: 'Повышенное качество, немного медленнее',
    source: ModelSource.ollama,
    variant: 'q5_k_m',
    files: [],
    languages: ['🇬🇧 English'],
    size: '103 MB',
    contextSize: 2048,
    metadata: {
      'recommended': false,
      'speed': 'medium',
    },
  );
  
  static const braindlerQ8 = PresetModel(
    id: 'nativemind/braindler',
    name: 'Braindler Q8',
    description: 'Высокое качество для мощных устройств',
    source: ModelSource.ollama,
    variant: 'q8_0',
    files: [],
    languages: ['🇬🇧 English'],
    size: '140 MB',
    contextSize: 2048,
    metadata: {
      'recommended': false,
      'speed': 'slow',
    },
  );
  
  static const braindlerF16 = PresetModel(
    id: 'nativemind/braindler',
    name: 'Braindler F16',
    description: 'Максимальное качество, требует много ресурсов',
    source: ModelSource.ollama,
    variant: 'f16',
    files: [],
    languages: ['🇬🇧 English'],
    size: '256 MB',
    contextSize: 2048,
    metadata: {
      'recommended': false,
      'speed': 'very_slow',
    },
  );
  
  /// Все предустановленные модели
  static const List<PresetModel> all = [
    shridharMultimodal,
    braindlerQ2K,
    braindlerQ4K,
    braindlerQ5K,
    braindlerQ8,
    braindlerF16,
  ];
  
  /// Получить модели по источнику
  static List<PresetModel> bySource(ModelSource source) {
    return all.where((model) => model.source == source).toList();
  }
  
  /// Получить рекомендуемые модели
  static List<PresetModel> get recommended {
    return all.where((model) {
      final isRecommended = model.metadata?['recommended'] as bool?;
      return isRecommended == true;
    }).toList();
  }
  
  /// Найти модель по ID
  static PresetModel? findById(String id, {String? variant}) {
    return all.firstWhere(
      (model) {
        if (variant != null) {
          return model.id == id && model.variant == variant;
        }
        return model.id == id;
      },
      orElse: () => all.first, // fallback
    );
  }
}


