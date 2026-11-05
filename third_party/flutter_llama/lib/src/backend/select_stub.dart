import 'backend.dart';

/// Web (no `dart:io`): nothing runs on device.
LlamaBackend createPlatformBackend() => const UnsupportedBackend();
