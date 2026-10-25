import 'media_download_stub.dart'
    if (dart.library.io) 'media_download_io.dart' as impl;

/// Fetches [url] and saves the image to the device (gallery on Android,
/// Downloads folder on Windows/desktop). Uses dart:io on native platforms and
/// a stub on web so the web build still compiles.
Future<void> saveImageToDevice(String url, String filename) =>
    impl.saveImageToDevice(url, filename);
