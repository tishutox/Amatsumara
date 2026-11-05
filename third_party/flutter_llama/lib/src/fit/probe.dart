/// Device facts for [canLoad]: memory, disk, file size and the GGUF shape.
library;

import 'gguf_shape.dart' if (dart.library.js_interop) 'gguf_shape_stub.dart';
import 'probe_stub.dart' if (dart.library.io) 'probe_io.dart' as impl;

export 'gguf_shape.dart' if (dart.library.js_interop) 'gguf_shape_stub.dart' show GgufShape;

abstract class DeviceProbe {
  factory DeviceProbe.platform() => impl.platformProbe();
  bool get isSupported;

  /// Memory an app can use now (null = unknown).
  Future<int?> availableMemoryBytes();
  Future<int?> freeDiskBytes(String directory);
  int fileBytes(String path);
  GgufShape? shape(String path);
}

/// A probe with fixed numbers (tests; apps with their own memory figures).
class FixedProbe implements DeviceProbe {
  FixedProbe({this.memory, this.disk, this.files = const {}, this.shapes = const {}, this.isSupported = true});
  final int? memory;
  final int? disk;
  final Map<String, int> files;
  final Map<String, GgufShape> shapes;
  @override
  final bool isSupported;
  @override
  Future<int?> availableMemoryBytes() async => memory;
  @override
  Future<int?> freeDiskBytes(String directory) async => disk;
  @override
  int fileBytes(String path) => files[path] ?? 0;
  @override
  GgufShape? shape(String path) => shapes[path];
}
