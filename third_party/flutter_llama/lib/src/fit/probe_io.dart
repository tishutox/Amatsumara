import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

import 'gguf_shape.dart';
import 'probe.dart';

DeviceProbe platformProbe() => IoProbe();

/// Linux: /proc/meminfo and statvfs; Windows: GlobalMemoryStatusEx and GetDiskFreeSpaceExW; Android / iOS / macOS:
/// the plugin's `core.memory` / `core.freeDisk` (tasks 1.2 / 1.3), unknown until then.
class IoProbe implements DeviceProbe {
  static const _channel = MethodChannel('flutter_llama');

  @override
  bool get isSupported => true;

  @override
  Future<int?> availableMemoryBytes() async {
    try {
      if (Platform.isLinux) return linuxMemAvailable(File('/proc/meminfo').readAsStringSync());
      if (Platform.isWindows) return _windowsMemory();
      return (await _channel.invokeMethod<num>('core.memory'))?.toInt();
    } on Object {
      return null;
    }
  }

  @override
  Future<int?> freeDiskBytes(String directory) async {
    try {
      if (Platform.isLinux) return _statvfs(directory);
      if (Platform.isWindows) return _windowsDisk(directory);
      return (await _channel.invokeMethod<num>('core.freeDisk', {'path': directory}))?.toInt();
    } on Object {
      return null;
    }
  }

  @override
  int fileBytes(String path) => File(path).lengthSync();

  @override
  GgufShape? shape(String path) {
    try {
      return readGgufShape(path);
    } on Object {
      return null;
    }
  }

  static int? _statvfs(String dir) => using((a) {
        // struct statvfs on 64-bit Linux: f_bsize, f_frsize, f_blocks, f_bfree, f_bavail, … (8 bytes each).
        final buf = a<Uint64>(16);
        final statvfs = DynamicLibrary.process().lookupFunction<Int32 Function(Pointer<Utf8>, Pointer<Uint64>), int Function(Pointer<Utf8>, Pointer<Uint64>)>('statvfs');
        if (statvfs(dir.toNativeUtf8(allocator: a), buf) != 0) return null;
        return buf[1] * buf[4];
      });

  static int? _windowsMemory() => using((a) {
        // MEMORYSTATUSEX: dwLength, dwMemoryLoad, then ullTotalPhys, ullAvailPhys, … (64 bytes).
        final buf = a<Uint8>(64);
        buf.cast<Uint32>().value = 64;
        final f = DynamicLibrary.open('kernel32.dll').lookupFunction<Int32 Function(Pointer<Uint8>), int Function(Pointer<Uint8>)>('GlobalMemoryStatusEx');
        if (f(buf) == 0) return null;
        return (buf + 16).cast<Uint64>().value;
      });

  static int? _windowsDisk(String dir) => using((a) {
        final free = a<Uint64>();
        final f = DynamicLibrary.open('kernel32.dll').lookupFunction<Int32 Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>),
            int Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>)>('GetDiskFreeSpaceExW');
        if (f(dir.toNativeUtf16(allocator: a), free, nullptr, nullptr) == 0) return null;
        return free.value;
      });
}

/// `MemAvailable` from /proc/meminfo, in bytes.
int? linuxMemAvailable(String meminfo) {
  final m = RegExp(r'^MemAvailable:\s+(\d+) kB', multiLine: true).firstMatch(meminfo);
  return m == null ? null : int.parse(m.group(1)!) * 1024;
}
