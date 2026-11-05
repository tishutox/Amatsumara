/// Hand-written bindings of `src/core/flutter_llama_core.h` (keep in sync with the header).
library;

import 'dart:ffi';
import 'dart:io' show Platform;

final class FlLoadParams extends Struct {
  @Int32()
  external int nCtx;
  @Int32()
  external int nBatch;
  @Int32()
  external int nThreads;
  @Int32()
  external int nGpuLayers;
  @Int32()
  external int embeddings;
}

final class FlSampleParams extends Struct {
  @Float()
  external double temperature;
  @Float()
  external double topP;
  @Int32()
  external int topK;
  @Float()
  external double repeatPenalty;
  @Int32()
  external int repeatLastN;
  @Int32()
  external int maxTokens;
  @Uint32()
  external int seed;
  external Pointer<Pointer<Char>> stop;
}

final class FlMessage extends Struct {
  external Pointer<Char> role;
  external Pointer<Char> content;
}

final class FlUsage extends Struct {
  @Int32()
  external int promptTokens;
  @Int32()
  external int completionTokens;
  @Int32()
  external int stopReason;
}

final class FlModelFacts extends Struct {
  @Uint64()
  external int nParams;
  @Uint64()
  external int sizeBytes;
  @Int32()
  external int nCtxTrain;
  @Int32()
  external int nCtx;
  @Int32()
  external int nVocab;
  @Int32()
  external int hasTemplate;
}

typedef FlTokenCbNative = Int32 Function(Pointer<Void> user, Pointer<Char> piece, Int32 len);

const flErrArg = -1, flErrNotLoaded = -2, flErrTokenize = -3, flErrDecode = -4, flErrGrammar = -5, flErrContext = -6,
    flErrTemplate = -7, flErrBuffer = -8, flErrCancelled = -9, flErrEmbeddings = -10;

/// The core's functions, looked up once per isolate.
final class FlCore {
  FlCore(DynamicLibrary lib)
      : backendInit = lib.lookupFunction<Void Function(), void Function()>('fl_backend_init'),
        load = lib.lookupFunction<Pointer<Void> Function(Pointer<Char>, Pointer<FlLoadParams>, Pointer<Char>, Int32),
            Pointer<Void> Function(Pointer<Char>, Pointer<FlLoadParams>, Pointer<Char>, int)>('fl_load'),
        free = lib.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('fl_free'),
        applyChatTemplate = lib.lookupFunction<
            Int32 Function(Pointer<Void>, Pointer<FlMessage>, Int32, Pointer<Char>, Int32, Pointer<Char>, Int32, Pointer<Int32>),
            int Function(Pointer<Void>, Pointer<FlMessage>, int, Pointer<Char>, int, Pointer<Char>, int, Pointer<Int32>)>('fl_apply_chat_template'),
        generate = lib.lookupFunction<
            Int32 Function(Pointer<Void>, Pointer<Char>, Pointer<FlSampleParams>, Pointer<Char>, Pointer<NativeFunction<FlTokenCbNative>>, Pointer<Void>, Pointer<FlUsage>),
            int Function(Pointer<Void>, Pointer<Char>, Pointer<FlSampleParams>, Pointer<Char>, Pointer<NativeFunction<FlTokenCbNative>>, Pointer<Void>, Pointer<FlUsage>)>('fl_generate'),
        stop = lib.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('fl_stop'),
        tokenizeCount = lib.lookupFunction<Int32 Function(Pointer<Void>, Pointer<Char>, Int32), int Function(Pointer<Void>, Pointer<Char>, int)>('fl_tokenize_count'),
        meta = lib.lookupFunction<Int32 Function(Pointer<Void>, Pointer<Char>, Pointer<Char>, Int32), int Function(Pointer<Void>, Pointer<Char>, Pointer<Char>, int)>('fl_meta'),
        facts = lib.lookupFunction<Int32 Function(Pointer<Void>, Pointer<FlModelFacts>, Pointer<Char>, Int32), int Function(Pointer<Void>, Pointer<FlModelFacts>, Pointer<Char>, int)>('fl_facts'),
        labelLogprobs = lib.lookupFunction<Int32 Function(Pointer<Void>, Pointer<Char>, Pointer<Pointer<Char>>, Int32, Pointer<Float>),
            int Function(Pointer<Void>, Pointer<Char>, Pointer<Pointer<Char>>, int, Pointer<Float>)>('fl_label_logprobs'),
        embed = lib.lookupFunction<Int32 Function(Pointer<Void>, Pointer<Char>, Pointer<Float>, Int32), int Function(Pointer<Void>, Pointer<Char>, Pointer<Float>, int)>('fl_embed');

  final void Function() backendInit;
  final Pointer<Void> Function(Pointer<Char>, Pointer<FlLoadParams>, Pointer<Char>, int) load;
  final void Function(Pointer<Void>) free;
  final int Function(Pointer<Void>, Pointer<FlMessage>, int, Pointer<Char>, int, Pointer<Char>, int, Pointer<Int32>) applyChatTemplate;
  final int Function(Pointer<Void>, Pointer<Char>, Pointer<FlSampleParams>, Pointer<Char>, Pointer<NativeFunction<FlTokenCbNative>>, Pointer<Void>, Pointer<FlUsage>) generate;
  final void Function(Pointer<Void>) stop;
  final int Function(Pointer<Void>, Pointer<Char>, int) tokenizeCount;
  final int Function(Pointer<Void>, Pointer<Char>, Pointer<Char>, int) meta;
  final int Function(Pointer<Void>, Pointer<FlModelFacts>, Pointer<Char>, int) facts;
  final int Function(Pointer<Void>, Pointer<Char>, Pointer<Pointer<Char>>, int, Pointer<Float>) labelLogprobs;
  final int Function(Pointer<Void>, Pointer<Char>, Pointer<Float>, int) embed;

  static FlCore? _cached;

  /// The bundled library; `FLUTTER_LLAMA_CORE_LIB` overrides the path (tests, custom builds).
  static FlCore open() => _cached ??= FlCore(DynamicLibrary.open(Platform.environment['FLUTTER_LLAMA_CORE_LIB'] ??
      (Platform.isWindows ? 'flutter_llama_core.dll' : Platform.isMacOS ? 'libflutter_llama_core.dylib' : 'libflutter_llama_core.so')));
}
