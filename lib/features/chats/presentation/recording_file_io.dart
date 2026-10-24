import 'dart:typed_data';

import 'recording_file_io_stub.dart'
    if (dart.library.io) 'recording_file_io_io.dart' as impl;

/// Reads a recorded audio file into memory. Uses `dart:io` on desktop/mobile
/// and a stub on web so the web build still compiles.
Future<Uint8List> readRecordingFile(String path) => impl.readRecordingFile(path);
