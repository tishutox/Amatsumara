/// Windows / Linux: `dart:ffi` over the shared core. Blocking core calls run on helper isolates, so the UI isolate
/// never waits on llama.cpp; streamed pieces come back through a [SendPort].
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import '../ffi/bindings.dart';
import '../models/chat.dart';
import 'backend.dart';

LlamaError errorFromCore(int code, [String what = '']) => switch (code) {
      flErrNotLoaded => const ModelNotLoaded(),
      flErrGrammar => GrammarInvalid('The grammar did not parse$what.'),
      flErrContext => ContextOverflow('The prompt does not fit the context$what.'),
      flErrTemplate => const TemplateUnavailable(),
      flErrCancelled => const Cancelled(),
      _ => NativeFailure('Core error $code$what.', code),
    };

Pointer<Void> _ptr(int address) => Pointer<Void>.fromAddress(address);

class FfiBackend implements LlamaBackend {
  FfiBackend({FlCore Function()? open}) : _open = open ?? FlCore.open;
  final FlCore Function() _open;
  bool? _supported;
  int _model = 0;

  /// Serialises core calls: one generation (and one other call) per model at a time.
  Future<void> _tail = Future.value();
  Future<T> _serial<T>(Future<T> Function() f) {
    final r = _tail.then((_) => f());
    _tail = r.then((_) {}, onError: (_) {});
    return r;
  }

  @override
  bool get isSupported {
    if (_supported != null) return _supported!;
    try {
      _open();
      return _supported = true;
    } on Object {
      return _supported = false;
    }
  }

  FlCore get _core {
    if (!isSupported) throw const UnsupportedPlatform('libflutter_llama_core is not bundled with this app.');
    return _open();
  }

  int get _m {
    if (_model == 0) throw const ModelNotLoaded();
    return _model;
  }

  @override
  Future<void> load(String path, {int contextSize = 0, int gpuLayers = -1, int threads = 0, bool embeddings = false}) {
    _core;
    return _serial(() async {
      final old = _model;
      _model = 0;
      final (address, err) = await _loadIsolated(old, path, contextSize, gpuLayers, threads, embeddings);
      if (address == 0) throw NativeFailure(err.isEmpty ? 'Could not load $path' : err);
      _model = address;
    });
  }

  /// Static, so the isolate closure captures only its arguments (never `this`).
  static Future<(int, String)> _loadIsolated(int old, String path, int contextSize, int gpuLayers, int threads, bool embeddings) =>
      Isolate.run(() {
        final c = FlCore.open();
        if (old != 0) c.free(_ptr(old));
        c.backendInit();
        return using((a) {
          final p = a<FlLoadParams>()
            ..ref.nCtx = contextSize
            ..ref.nBatch = 0
            ..ref.nThreads = threads
            ..ref.nGpuLayers = gpuLayers
            ..ref.embeddings = embeddings ? 1 : 0;
          final err = a<Char>(512);
          final m = c.load(path.toNativeUtf8(allocator: a).cast(), p, err, 512);
          return (m.address, m.address == 0 ? err.cast<Utf8>().toDartString() : '');
        });
      });

  @override
  Future<bool> get isLoaded async => _model != 0;

  @override
  Future<String> applyTemplate(List<({String role, String content})> messages, {String? template, bool addAssistant = true}) async {
    final c = _core, m = _m;
    return using((a) {
      final msgs = a<FlMessage>(messages.length);
      for (var i = 0; i < messages.length; i++) {
        msgs[i].role = messages[i].role.toNativeUtf8(allocator: a).cast();
        msgs[i].content = messages[i].content.toNativeUtf8(allocator: a).cast();
      }
      final tmpl = template == null ? nullptr : template.toNativeUtf8(allocator: a).cast<Char>();
      final needed = a<Int32>();
      var cap = 4096 + messages.fold<int>(0, (s, x) => s + utf8.encode(x.content).length * 2);
      for (var attempt = 0; attempt < 2; attempt++) {
        final out = a<Uint8>(cap);
        final r = c.applyChatTemplate(_ptr(m), msgs, messages.length, tmpl, addAssistant ? 1 : 0, out.cast(), cap, needed);
        if (r >= 0) return utf8.decode(out.asTypedList(r), allowMalformed: true);
        if (r != flErrBuffer) throw errorFromCore(r, ' (chat template)');
        cap = needed.value + 1;
      }
      throw const NativeFailure('Chat template buffer');
    });
  }

  @override
  Stream<Object> generate(String prompt, RawSampling s, {String? grammar}) {
    final m = _m;
    // Cancelling the subscription stops the native generation (the pieces already sent are dropped).
    var cancelled = false;
    final out = StreamController<Object>(onCancel: () {
      cancelled = true;
      _core.stop(_ptr(m));
    });
    _core;
    unawaited(_serial(() async {
      // Cancelled while queued: the core resets its stop flag when a generation starts, so skip it here.
      if (cancelled) return;
      final port = ReceivePort();
      final done = Completer<void>();
      port.listen((msg) {
        if (msg is String) {
          if (!out.isClosed) out.add(msg);
        } else if (msg is List) {
          final code = msg[0] as int;
          if (out.isClosed) {
            // cancelled by the listener
          } else if (code < 0 && code != flErrCancelled) {
            out.addError(errorFromCore(code, ' (generate)'));
          } else {
            out.add(RawDone(code == flErrCancelled ? ChatStopReason.cancelled : _reason(msg[3] as int), msg[1] as int, msg[2] as int));
          }
          port.close();
          done.complete();
        }
      });
      final send = port.sendPort;
      try {
        await _generateIsolated(m, prompt, s, grammar, send);
      } on Object catch (e) {
        if (!done.isCompleted) {
          out.addError(NativeFailure('$e'));
          port.close();
          done.complete();
        }
      }
      await done.future;
      await out.close();
    }));
    return out.stream;
  }

  static ChatStopReason _reason(int r) => switch (r) {
        1 => ChatStopReason.maxTokens,
        2 => ChatStopReason.stopString,
        3 => ChatStopReason.cancelled,
        _ => ChatStopReason.eos,
      };

  static Future<void> _generateIsolated(int m, String prompt, RawSampling s, String? grammar, SendPort send) =>
      Isolate.run(() => _generateOn(m, prompt, s, grammar, send));

  /// Runs on a helper isolate: the core calls back on this same thread, so an isolate-local callback is enough.
  static void _generateOn(int m, String prompt, RawSampling s, String? grammar, SendPort send) {
    final c = FlCore.open();
    final cb = NativeCallable<FlTokenCbNative>.isolateLocal((Pointer<Void> _, Pointer<Char> piece, int len) {
      send.send(utf8.decode(piece.cast<Uint8>().asTypedList(len), allowMalformed: true));
      return 0;
    }, exceptionalReturn: 1);
    try {
      using((a) {
        Pointer<Pointer<Char>> stop = nullptr;
        if (s.stop.isNotEmpty) {
          stop = a<Pointer<Char>>(s.stop.length + 1);
          for (var i = 0; i < s.stop.length; i++) {
            stop[i] = s.stop[i].toNativeUtf8(allocator: a).cast();
          }
          stop[s.stop.length] = nullptr;
        }
        final sp = a<FlSampleParams>()
          ..ref.temperature = s.temperature
          ..ref.topP = s.topP
          ..ref.topK = s.topK
          ..ref.repeatPenalty = s.repeatPenalty
          ..ref.repeatLastN = 0
          ..ref.maxTokens = s.maxTokens
          ..ref.seed = s.seed
          ..ref.stop = stop;
        final usage = a<FlUsage>();
        final r = c.generate(_ptr(m), prompt.toNativeUtf8(allocator: a).cast(), sp,
            grammar == null ? nullptr : grammar.toNativeUtf8(allocator: a).cast(), cb.nativeFunction, nullptr, usage);
        send.send([r, usage.ref.promptTokens, usage.ref.completionTokens, usage.ref.stopReason]);
      });
    } finally {
      cb.close();
    }
  }

  @override
  Future<void> stop() async {
    if (_model != 0) _core.stop(_ptr(_model));
  }

  @override
  Future<int> countTokens(String text, {bool addSpecial = false}) async {
    final c = _core, m = _m;
    final r = using((a) => c.tokenizeCount(_ptr(m), text.toNativeUtf8(allocator: a).cast(), addSpecial ? 1 : 0));
    if (r < 0) throw errorFromCore(r, ' (tokenize)');
    return r;
  }

  @override
  Future<String?> meta(String key) async {
    final c = _core, m = _m;
    return using((a) {
      final k = key.toNativeUtf8(allocator: a).cast<Char>();
      var cap = 1024;
      for (var attempt = 0; attempt < 3; attempt++) {
        final out = a<Uint8>(cap);
        final r = c.meta(_ptr(m), k, out.cast(), cap);
        if (r == flErrTemplate || r == -1) return null;
        if (r == flErrBuffer || r >= cap) {
          cap = (r >= cap ? r + 1 : cap * 64);
          continue;
        }
        if (r < 0) throw errorFromCore(r, ' (meta)');
        return utf8.decode(out.asTypedList(r), allowMalformed: true);
      }
      return null;
    });
  }

  @override
  Future<RawFacts> facts() async {
    final c = _core, m = _m;
    return using((a) {
      final f = a<FlModelFacts>();
      final desc = a<Char>(256);
      final r = c.facts(_ptr(m), f, desc, 256);
      if (r < 0) throw errorFromCore(r, ' (facts)');
      return RawFacts(
        parameters: f.ref.nParams,
        sizeBytes: f.ref.sizeBytes,
        trainedContext: f.ref.nCtxTrain,
        context: f.ref.nCtx,
        hasTemplate: f.ref.hasTemplate != 0,
        description: desc.cast<Utf8>().toDartString(),
      );
    });
  }

  @override
  Future<List<double>> labelLogprobs(String prompt, List<String> labels) {
    final m = _m;
    _core;
    return _serial(() async {
      final (r, out) = await _logprobsIsolated(m, prompt, labels);
      if (r < 0) throw errorFromCore(r, ' (classify)');
      return out;
    });
  }

  @override
  Future<List<double>> embed(String text) {
    final m = _m;
    _core;
    return _serial(() async {
      final (r, out) = await _embedIsolated(m, text);
      if (r == flErrEmbeddings) throw const NativeFailure('This model was not loaded with embeddings.', flErrEmbeddings);
      if (r < 0) throw errorFromCore(r, ' (embed)');
      return out;
    });
  }

  static Future<(int, List<double>)> _logprobsIsolated(int m, String prompt, List<String> labels) => Isolate.run(() => using((a) {
        final c = FlCore.open();
        final ls = a<Pointer<Char>>(labels.length);
        for (var i = 0; i < labels.length; i++) {
          ls[i] = labels[i].toNativeUtf8(allocator: a).cast();
        }
        final out = a<Float>(labels.length);
        final r = c.labelLogprobs(_ptr(m), prompt.toNativeUtf8(allocator: a).cast(), ls, labels.length, out);
        return (r, List<double>.of(out.asTypedList(labels.length)));
      }));

  static Future<(int, List<double>)> _embedIsolated(int m, String text) => Isolate.run(() => using((a) {
        final c = FlCore.open();
        const cap = 16384;
        final out = a<Float>(cap);
        final r = c.embed(_ptr(m), text.toNativeUtf8(allocator: a).cast(), out, cap);
        return (r, r > 0 ? List<double>.of(out.asTypedList(r)) : const <double>[]);
      }));

  @override
  Future<void> unload() => _serial(() async {
        final m = _model;
        _model = 0;
        if (m != 0) _core.free(_ptr(m));
      });
}
