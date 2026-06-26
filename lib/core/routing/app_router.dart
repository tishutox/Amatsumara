import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
export 'package:lumii_quest/core/routing/profile_links.dart';
import 'package:lumii_quest/features/chats/presentation/chat_detail_page.dart';
import 'package:lumii_quest/features/notifications/presentation/notifications_page.dart';
import 'package:lumii_quest/features/friends/presentation/friends_page.dart';
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
    GoRoute(path: '/friends', builder: (_, _) => const FriendsPage()),
    GoRoute(
      path: '/chats/:conversationId',
      builder: (_, state) => ChatDetailPage(
        conversationId: state.pathParameters['conversationId'] ?? '',
        friendId: state.uri.queryParameters['friendId'] ?? '',
        displayName: state.uri.queryParameters['name'] ?? 'Chat',
      ),
    ),
    GoRoute(
      path: '/notifications',
      builder: (_, _) => const NotificationsPage(),
    ),
    GoRoute(
      path: '/:username',
      redirect: (_, state) => '/u/${state.pathParameters['username']}',
    ),
  ],
  errorBuilder: (_, state) =>
      Scaffold(body: Center(child: Text('Page not found: ${state.uri.path}'))),
);
