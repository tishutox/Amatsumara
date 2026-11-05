import 'dart:io' show Platform;

import 'backend.dart';
import 'channel_backend.dart';
import 'ffi_backend.dart';

/// Android / iOS / macOS: the owner's channel plugins; Windows / Linux: FFI over the shared core.
LlamaBackend createPlatformBackend() {
  if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) return ChannelBackend();
  if (Platform.isLinux || Platform.isWindows) return FfiBackend();
  return const UnsupportedBackend();
}
