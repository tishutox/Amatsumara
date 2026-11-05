/// The native side as one interface (sdd-flutter-llama-agent 2.1): method channels on Android / iOS / macOS, FFI on
/// Windows / Linux, unsupported on the web. The 1.2 API (chat, classify, …) runs on it; tests inject a fake.
library;

import '../models/chat.dart';

/// Sampling for one raw generation.
class RawSampling {
  const RawSampling({this.temperature = 0.7, this.topP = 0.9, this.topK = 40, this.repeatPenalty = 1.1, this.maxTokens = 512, this.seed = 0, this.stop = const []});
  final double temperature;
  final double topP;
  final int topK;
  final double repeatPenalty;
  final int maxTokens;
  final int seed;
  final List<String> stop;
}

/// The end of a raw generation.
class RawDone {
  const RawDone(this.reason, this.promptTokens, this.completionTokens);
  final ChatStopReason reason;
  final int promptTokens;
  final int completionTokens;
}

/// Facts of the loaded model.
class RawFacts {
  const RawFacts({required this.parameters, required this.sizeBytes, required this.trainedContext, required this.context, required this.hasTemplate, required this.description});
  final int parameters;
  final int sizeBytes;
  final int trainedContext;
  final int context;
  final bool hasTemplate;
  final String description;
}

abstract interface class LlamaBackend {
  bool get isSupported;

  /// The backend's own load (desktop FFI); mobile backends use the 1.1 `loadModel` channel call.
  Future<void> load(String path, {int contextSize = 0, int gpuLayers = -1, int threads = 0, bool embeddings = false});
  Future<bool> get isLoaded;

  /// Formats [messages] (role / content pairs) with [template] (null = the model's own).
  Future<String> applyTemplate(List<({String role, String content})> messages, {String? template, bool addAssistant = true});

  /// Streams UTF-8 pieces; the last event is a [RawDone] (as a `Stream<Object>`: `String` pieces, then `RawDone`).
  Stream<Object> generate(String prompt, RawSampling sampling, {String? grammar});
  Future<void> stop();
  Future<int> countTokens(String text, {bool addSpecial = false});
  Future<String?> meta(String key);
  Future<RawFacts> facts();
  Future<List<double>> labelLogprobs(String prompt, List<String> labels);
  Future<List<double>> embed(String text);
  Future<void> unload();
}

/// The web (and any platform without a native library).
class UnsupportedBackend implements LlamaBackend {
  const UnsupportedBackend();
  @override
  bool get isSupported => false;
  Never _no() => throw const UnsupportedPlatform();
  @override
  Future<void> load(String path, {int contextSize = 0, int gpuLayers = -1, int threads = 0, bool embeddings = false}) async => _no();
  @override
  Future<bool> get isLoaded async => false;
  @override
  Future<String> applyTemplate(List<({String role, String content})> messages, {String? template, bool addAssistant = true}) async => _no();
  @override
  Stream<Object> generate(String prompt, RawSampling sampling, {String? grammar}) => Stream.error(const UnsupportedPlatform());
  @override
  Future<void> stop() async {}
  @override
  Future<int> countTokens(String text, {bool addSpecial = false}) async => _no();
  @override
  Future<String?> meta(String key) async => _no();
  @override
  Future<RawFacts> facts() async => _no();
  @override
  Future<List<double>> labelLogprobs(String prompt, List<String> labels) async => _no();
  @override
  Future<List<double>> embed(String text) async => _no();
  @override
  Future<void> unload() async {}
}
