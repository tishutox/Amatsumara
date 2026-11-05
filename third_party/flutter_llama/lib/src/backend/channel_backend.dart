/// Android / iOS / macOS: the owner's method-channel plugins, extended with `core.*` methods over the shared core
/// (tasks 1.2 / 1.3). The 1.1 names (`loadModel`, `unloadModel`, `stopGeneration`, `flutter_llama/stream`) are unchanged.
library;

import 'dart:async';

import 'package:flutter/services.dart';

import '../models/chat.dart';
import 'backend.dart';

/// Wire protocol of the `core.*` methods: shared by the Kotlin and Swift sides.
abstract final class CoreChannel {
  static const methods = MethodChannel('flutter_llama');

  /// Events of `core.generate`: `{"piece": String}` …, then `{"done": int reason, "prompt": int, "completion": int}`
  /// or a platform error.
  static const generation = EventChannel('flutter_llama/core_stream');

  static const applyTemplate = 'core.applyTemplate';
  static const generate = 'core.generate';
  static const stop = 'core.stop';
  static const countTokens = 'core.countTokens';
  static const meta = 'core.meta';
  static const facts = 'core.facts';
  static const labelLogprobs = 'core.labelLogprobs';
  static const embed = 'core.embed';
  static const isLoaded = 'core.isLoaded';
}

/// Maps a core stop reason (`fl_usage.stop_reason`) to Dart.
ChatStopReason stopReasonFromCore(int r) => switch (r) {
      1 => ChatStopReason.maxTokens,
      2 => ChatStopReason.stopString,
      3 => ChatStopReason.cancelled,
      _ => ChatStopReason.eos,
    };

/// Maps a platform error code to a typed [LlamaError].
LlamaError errorFromPlatform(PlatformException e) => switch (e.code) {
      'NOT_LOADED' => const ModelNotLoaded(),
      'GRAMMAR' => GrammarInvalid(e.message ?? 'grammar'),
      'CONTEXT' => ContextOverflow(e.message ?? 'context'),
      'TEMPLATE' => const TemplateUnavailable(),
      'CANCELLED' => const Cancelled(),
      _ => NativeFailure(e.message ?? e.code),
    };

class ChannelBackend implements LlamaBackend {
  ChannelBackend({MethodChannel? methods, EventChannel? generation})
      : _m = methods ?? CoreChannel.methods,
        _events = generation ?? CoreChannel.generation;
  final MethodChannel _m;
  final EventChannel _events;

  @override
  bool get isSupported => true;

  Future<T?> _call<T>(String method, [Object? args]) async {
    try {
      return await _m.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw errorFromPlatform(e);
    } on MissingPluginException {
      throw const UnsupportedPlatform('This platform plugin predates flutter_llama 1.2 core methods.');
    }
  }

  @override
  Future<void> load(String path, {int contextSize = 0, int gpuLayers = -1, int threads = 0, bool embeddings = false}) async {
    final ok = await _call<bool>('loadModel', {
      'modelPath': path,
      'nThreads': threads <= 0 ? 4 : threads,
      'nGpuLayers': gpuLayers,
      'contextSize': contextSize <= 0 ? 2048 : contextSize,
      'batchSize': 512,
      'useGpu': gpuLayers != 0,
      'verbose': false,
      'embeddings': embeddings,
    });
    if (ok != true) throw NativeFailure('loadModel failed: $path');
  }

  @override
  Future<bool> get isLoaded async => (await _call<bool>(CoreChannel.isLoaded)) ?? false;

  @override
  Future<String> applyTemplate(List<({String role, String content})> messages, {String? template, bool addAssistant = true}) async =>
      (await _call<String>(CoreChannel.applyTemplate, {
        'messages': [for (final m in messages) {'role': m.role, 'content': m.content}],
        'template': template,
        'addAssistant': addAssistant,
      }))!;

  @override
  Stream<Object> generate(String prompt, RawSampling s, {String? grammar}) {
    late StreamController<Object> out;
    StreamSubscription<dynamic>? sub;
    out = StreamController<Object>(
      onListen: () {
        sub = _events.receiveBroadcastStream().listen(
          (e) {
            final m = (e as Map).cast<String, Object?>();
            if (m['piece'] case final String p) {
              out.add(p);
            } else if (m['done'] case final int r) {
              out.add(RawDone(stopReasonFromCore(r), (m['prompt'] as int?) ?? 0, (m['completion'] as int?) ?? 0));
              out.close();
              sub?.cancel();
            }
          },
          onError: (Object e) {
            out.addError(e is PlatformException ? errorFromPlatform(e) : e);
            out.close();
          },
        );
        _call<void>(CoreChannel.generate, {
          'prompt': prompt,
          'temperature': s.temperature,
          'topP': s.topP,
          'topK': s.topK,
          'repeatPenalty': s.repeatPenalty,
          'maxTokens': s.maxTokens,
          'seed': s.seed,
          'stop': s.stop,
          'grammar': grammar,
        }).catchError((Object e) {
          if (!out.isClosed) {
            out.addError(e);
            out.close();
          }
        });
      },
      onCancel: () async {
        if (!out.isClosed) unawaited(_call<void>(CoreChannel.stop).catchError((Object _) {}));
        await sub?.cancel();
      },
    );
    return out.stream;
  }

  @override
  Future<void> stop() => _call<void>(CoreChannel.stop);

  @override
  Future<int> countTokens(String text, {bool addSpecial = false}) async =>
      (await _call<int>(CoreChannel.countTokens, {'text': text, 'addSpecial': addSpecial}))!;

  @override
  Future<String?> meta(String key) => _call<String>(CoreChannel.meta, {'key': key});

  @override
  Future<RawFacts> facts() async {
    final m = (await _call<Map<Object?, Object?>>(CoreChannel.facts))!.cast<String, Object?>();
    return RawFacts(
      parameters: (m['parameters'] as num).toInt(),
      sizeBytes: (m['sizeBytes'] as num).toInt(),
      trainedContext: m['trainedContext'] as int,
      context: m['context'] as int,
      hasTemplate: m['hasTemplate'] as bool,
      description: m['description'] as String,
    );
  }

  @override
  Future<List<double>> labelLogprobs(String prompt, List<String> labels) async =>
      [for (final v in (await _call<List<Object?>>(CoreChannel.labelLogprobs, {'prompt': prompt, 'labels': labels}))!) (v as num).toDouble()];

  @override
  Future<List<double>> embed(String text) async =>
      [for (final v in (await _call<List<Object?>>(CoreChannel.embed, {'text': text}))!) (v as num).toDouble()];

  @override
  Future<void> unload() => _call<void>('unloadModel');
}
