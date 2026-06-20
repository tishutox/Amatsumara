import 'package:lumii_quest/app/app.dart';
import 'package:lumii_quest/core/routing/url_strategy.dart';
import 'package:lumii_quest/core/routing/protocol_registration.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY'),
);

Future<void> _configureOrientation() async {
  final views = WidgetsBinding.instance.platformDispatcher.views;
  if (views.isEmpty) {
    return;
  }

  final view = views.first;
  final logicalSize = view.physicalSize / view.devicePixelRatio;
  final isPhone = logicalSize.shortestSide < 600;

  if (isPhone) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    return;
  }

  await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureUrlStrategy();
  registerAppProtocol();
  if (_supabaseUrl.isEmpty || _supabasePublishableKey.isEmpty) {
    throw StateError(
      'Supabase configuration is missing. Start Flutter with '
      '--dart-define=SUPABASE_URL=... and '
      '--dart-define=SUPABASE_PUBLISHABLE_KEY=...',
    );
  }
  await Supabase.initialize(
    url: _supabaseUrl,
    publishableKey: _supabasePublishableKey,
  );
  await _configureOrientation();
  runApp(const LumiiQuestApp());
}
