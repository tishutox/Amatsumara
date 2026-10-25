import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

Future<void> saveImageToDevice(String url, String filename) async {
  final bytes = await _fetchBytes(url);

  if (defaultTargetPlatform == TargetPlatform.android) {
    await Gal.putImageBytes(bytes, name: filename);
    return;
  }

  final dir = await getDownloadsDirectory();
  if (dir == null) {
    throw const FileSystemException('Downloads folder is not available.');
  }
  final file = File('${dir.path}${Platform.pathSeparator}$filename');
  await file.writeAsBytes(bytes, flush: true);
}

Future<Uint8List> _fetchBytes(String url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException('Download failed (${response.statusCode}).');
    }
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
    }
    return Uint8List.fromList(bytes);
  } finally {
    client.close();
  }
}
