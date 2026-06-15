import 'package:friendship/core/theme/app_theme.dart';
import 'package:friendship/widgets/app_shell.dart';
import 'package:flutter/material.dart';

class FriendshipApp extends StatelessWidget {
  const FriendshipApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Friendship',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const AppShell(),
    );
  }
}
