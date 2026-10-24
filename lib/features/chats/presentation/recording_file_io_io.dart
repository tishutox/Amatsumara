import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> readRecordingFile(String path) => File(path).readAsBytes();
