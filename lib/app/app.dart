import 'package:flutter/material.dart';
import 'package:lumii_quest/core/routing/app_router.dart';
import 'package:lumii_quest/core/theme/app_theme.dart';

class LumiiQuestApp extends StatelessWidget {
  const LumiiQuestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Amatsumara',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: appRouter,
    );
  }
}
