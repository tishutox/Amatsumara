/// canLoad: whether a model fits this device (sdd-flutter-llama-agent 2.4).
library;

import '../models/chat.dart';
import 'probe.dart';

/// A model to check: a GGUF on disk, or one still to download.
sealed class ModelRef {
  const ModelRef();

  /// A GGUF file; its header gives the KV-cache shape.
  const factory ModelRef.file(String path, {int contextSize}) = FileModelRef;

  /// A model to download: [bytes] to [directory], needing [ramBytes] when known.
  const factory ModelRef.download({required int bytes, required String directory, int? ramBytes, int contextSize}) = DownloadModelRef;
}

class FileModelRef extends ModelRef {
  const FileModelRef(this.path, {this.contextSize = 2048});
  final String path;
  final int contextSize;
}

class DownloadModelRef extends ModelRef {
  const DownloadModelRef({required this.bytes, required this.directory, this.ramBytes, this.contextSize = 2048});
  final int bytes;
  final String directory;
  final int? ramBytes;
  final int contextSize;
}

/// The bytes a load needs: weights × 1.2 (compute buffers, runtime) plus the f16 KV cache for the context.
int estimateNeedBytes({required int fileBytes, int? kvBytes}) => (fileBytes * 1.2).round() + (kvBytes ?? (fileBytes * 0.1).round());

Future<DeviceFit> canLoad(ModelRef ref, {DeviceProbe? probe}) async {
  final p = probe ?? DeviceProbe.platform();
  if (!p.isSupported) return const DeviceFit(ok: false, needBytes: 0, availableBytes: 0, reason: 'unsupported_platform');
  final int need;
  switch (ref) {
    case FileModelRef(:final path, :final contextSize):
      final shape = p.shape(path);
      need = estimateNeedBytes(fileBytes: p.fileBytes(path), kvBytes: shape?.kvBytes(contextSize));
    case DownloadModelRef(:final bytes, :final directory, :final ramBytes):
      final disk = await p.freeDiskBytes(directory);
      if (disk != null && disk < bytes) return DeviceFit(ok: false, needBytes: bytes, availableBytes: disk, reason: 'too_large_disk');
      need = ramBytes ?? estimateNeedBytes(fileBytes: bytes);
  }
  final mem = await p.availableMemoryBytes();
  if (mem == null) return DeviceFit(ok: true, needBytes: need, availableBytes: 0, reason: 'unknown_memory');
  return DeviceFit(ok: need <= mem, needBytes: need, availableBytes: mem, reason: need <= mem ? null : 'too_large_ram');
}
