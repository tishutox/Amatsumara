import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class ApkUpdate {
  const ApkUpdate._();

  // Replace with your real hosted APK URL or GitHub release asset URL.
  static const String latestApkUrl =
      'https://example.com/downloads/friendship-android-v1.apk';

  static Future<void> openLatestApk(BuildContext context) async {
    final uri = Uri.parse(latestApkUrl);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!context.mounted) {
      return;
    }

    if (!launched) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('APK-Link konnte nicht geoeffnet werden.')),
      );
    }
  }
}
