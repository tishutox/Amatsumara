import 'package:lumii_quest/app/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> _configureOrientation() async {
  final views = WidgetsBinding.instance.platformDispatcher.views;
  if (views.isEmpty) {
    return;
  }

  final view = views.first;
  final logicalSize = view.physicalSize / view.devicePixelRatio;
  final isPhone = logicalSize.shortestSide < 600;

  if (isPhone) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    return;
  }

  await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _configureOrientation();
  runApp(const LumiiQuestApp());
}
