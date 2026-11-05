/// Picks the backend for this platform; `dart:ffi` and `dart:io` stay out of web builds.
library;

export 'select_stub.dart' if (dart.library.io) 'select_io.dart';
