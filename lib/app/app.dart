import 'package:lumii_quest/core/theme/app_theme.dart';
import 'package:lumii_quest/widgets/app_shell.dart';
import 'package:flutter/material.dart';

class LumiiQuestApp extends StatelessWidget {
  const LumiiQuestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lumii Quest',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const AppShell(),
    );
  }
}
