import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lumii_quest/features/profile/presentation/edit_profile_page.dart';
import 'package:lumii_quest/features/profile/presentation/public_profile_page.dart';
import 'package:lumii_quest/widgets/app_shell.dart';

final appRouter = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, _) => const AppShell()),
    GoRoute(
      path: '/u/:username',
      builder: (_, state) =>
          PublicProfilePage(username: state.pathParameters['username'] ?? ''),
    ),
    GoRoute(path: '/edit-profile', builder: (_, _) => const EditProfilePage()),
  ],
  errorBuilder: (_, state) =>
      Scaffold(body: Center(child: Text('Page not found: ${state.uri.path}'))),
);

String? profileLocationFromUri(Uri uri) {
  if (uri.scheme == 'lumiiquest' && uri.host == 'u') {
    final username = uri.pathSegments.firstOrNull;
    return username == null ? null : '/u/$username';
  }

  final segments = uri.pathSegments;
  final userSegment = segments.lastIndexOf('u');
  if (userSegment >= 0 && userSegment + 1 < segments.length) {
    return '/u/${segments[userSegment + 1]}';
  }
  return null;
}
