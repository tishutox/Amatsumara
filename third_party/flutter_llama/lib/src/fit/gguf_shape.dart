/// Reads the GGUF header (metadata only, no tensors) to size a model before loading it.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// What a load needs to know: the architecture, its context and the shape of the KV cache.
class GgufShape {
  const GgufShape({required this.architecture, required this.layers, required this.embedding, required this.heads, required this.headsKv, this.keyLength, this.trainedContext, this.name, this.license});
  final String architecture;
  final int layers;
  final int embedding;
  final int heads;
  final int headsKv;
  final int? keyLength;
  final int? trainedContext;
  final String? name;
  final String? license;

  /// f16 K + V cache bytes for [context] tokens.
  int kvBytes(int context) {
    final head = keyLength ?? (heads == 0 ? 0 : embedding ~/ heads);
    return 2 * layers * context * head * headsKv * 2;
  }
}

/// Sequential reader over a [RandomAccessFile] with a buffer (tokenizer arrays have tens of thousands of strings).
class _Reader {
  _Reader(this._f);
  final RandomAccessFile _f;
  Uint8List _buf = Uint8List(0);
  int _pos = 0;

  void _need(int n) {
    if (_pos + n <= _buf.length) return;
    final rest = _buf.sublist(_pos);
    final more = _f.readSync(n - rest.length > 1 << 20 ? n - rest.length : 1 << 20);
    if (rest.length + more.length < n) throw const FormatException('truncated GGUF');
    _buf = Uint8List(rest.length + more.length)
      ..setAll(0, rest)
      ..setAll(rest.length, more);
    _pos = 0;
  }

  ByteData _bytes(int n) {
    _need(n);
    final d = ByteData.sublistView(_buf, _pos, _pos + n);
    _pos += n;
    return d;
  }

  int u32() => _bytes(4).getUint32(0, Endian.little);
  int u64() => _bytes(8).getUint64(0, Endian.little);
  String str() {
    final n = u64();
    _need(n);
    final s = utf8.decode(_buf.sublist(_pos, _pos + n), allowMalformed: true);
    _pos += n;
    return s;
  }

  void skip(int n) {
    while (n > 0) {
      final take = n > 1 << 20 ? 1 << 20 : n;
      _need(take);
      _pos += take;
      n -= take;
    }
  }

  static const _sizes = {0: 1, 1: 1, 2: 2, 3: 2, 4: 4, 5: 4, 6: 4, 7: 1, 10: 8, 11: 8, 12: 8};

  /// A scalar or string value; arrays are skipped (null).
  Object? value(int type) {
    switch (type) {
      case 8:
        return str();
      case 9:
        final t = u32(), n = u64();
        if (t == 8) {
          for (var i = 0; i < n; i++) {
            skip(u64());
          }
        } else if (t == 9) {
          throw const FormatException('nested GGUF arrays');
        } else {
          skip(n * (_sizes[t] ?? (throw FormatException('GGUF type $t'))));
        }
        return null;
      default:
        final size = _sizes[type] ?? (throw FormatException('GGUF type $type'));
        final d = _bytes(size);
        return switch (type) {
          0 => d.getUint8(0),
          1 => d.getInt8(0),
          2 => d.getUint16(0, Endian.little),
          3 => d.getInt16(0, Endian.little),
          4 => d.getUint32(0, Endian.little),
          5 => d.getInt32(0, Endian.little),
          6 => d.getFloat32(0, Endian.little),
          7 => d.getUint8(0) != 0,
          10 => d.getUint64(0, Endian.little),
          11 => d.getInt64(0, Endian.little),
          _ => d.getFloat64(0, Endian.little),
        };
    }
  }
}

/// The shape of the GGUF at [path]; throws [FormatException] for anything else.
GgufShape readGgufShape(String path) {
  final f = File(path).openSync();
  try {
    final r = _Reader(f);
    if (r.u32() != 0x46554747) throw const FormatException('not a GGUF file'); // "GGUF"
    final version = r.u32();
    if (version < 2) throw FormatException('GGUF v$version');
    r.u64(); // tensors
    final n = r.u64();
    final kv = <String, Object?>{};
    for (var i = 0; i < n; i++) {
      final key = r.str();
      kv[key] = r.value(r.u32());
    }
    final arch = kv['general.architecture'] as String? ?? (throw const FormatException('no general.architecture'));
    int k(String s, [int d = 0]) => (kv['$arch.$s'] as num?)?.toInt() ?? d;
    final heads = k('attention.head_count');
    return GgufShape(
      architecture: arch,
      layers: k('block_count'),
      embedding: k('embedding_length'),
      heads: heads,
      headsKv: k('attention.head_count_kv', heads),
      keyLength: (kv['$arch.attention.key_length'] as num?)?.toInt(),
      trainedContext: (kv['$arch.context_length'] as num?)?.toInt(),
      name: kv['general.name'] as String?,
      license: kv['general.license'] as String?,
    );
  } finally {
    f.closeSync();
  }
}
