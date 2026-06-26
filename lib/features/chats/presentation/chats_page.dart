import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lumii_quest/core/responsive/content_layout.dart';
import 'package:lumii_quest/features/chats/crypto/chat_crypto_service.dart';
import 'package:lumii_quest/features/chats/data/chat_repository.dart';
import 'package:remixicon/remixicon.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key});

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  final _repository = ChatRepository();
  final _crypto = ChatCryptoService();
  late Future<List<ChatPreview>> _chatsFuture;
  late final StreamSubscription<AuthState> _authSubscription;

  @override
  void initState() {
    super.initState();
    _chatsFuture = _loadChats();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      _,
    ) {
      if (mounted) {
        setState(() => _chatsFuture = _loadChats());
      }
    });
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  Future<List<ChatPreview>> _loadChats() async {
    if (Supabase.instance.client.auth.currentUser != null) {
      final identity = await _crypto.ensureDeviceIdentity();
      await _repository.upsertIdentityKey(identity.publicKey);
      await _repository.upsertDeviceKey(
        deviceId: identity.deviceId,
        publicKey: identity.publicKey,
        deviceName: identity.deviceName,
      );
    }
    return _repository.listChats();
  }

  void _reload() {
    setState(() => _chatsFuture = _loadChats());
  }

  Future<void> _refresh() async {
    final future = _loadChats();
    setState(() => _chatsFuture = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return const _ChatEmptyState(
        icon: Remix.lock_2_line,
        title: 'Sign in to chat',
        message: 'Your encrypted chats will appear here after you sign in.',
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: ContentLayout.pagePadding,
        children: [
          ContentLayout.widthBox(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Remix.shield_keyhole_line,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Chats are end-to-end encrypted. Messages are stored on the server only as encrypted payloads.',
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: _refresh,
                      icon: const Icon(Remix.refresh_line),
                    ),
                  ],
                ),
              ),
            ),
          ),
          ContentLayout.sectionGap,
          FutureBuilder<List<ChatPreview>>(
            future: _chatsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _ChatEmptyState(
                  icon: Remix.error_warning_line,
                  title: 'Chats could not be loaded',
                  message: 'Please run the updated Supabase SQL and try again.',
                  action: TextButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Remix.refresh_line),
                    label: const Text('Try again'),
                  ),
                );
              }

              final chats = snapshot.data ?? const [];
              if (chats.isEmpty) {
                return const _ChatEmptyState(
                  icon: Remix.message_3_line,
                  title: 'No chats yet',
                  message:
                      'When you become friends with someone, their private chat appears here.',
                );
              }

              return Column(
                children: [
                  for (final chat in chats) ...[
                    ContentLayout.widthBox(child: _ChatTile(chat: chat)),
                    ContentLayout.sectionGap,
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({required this.chat});

  final ChatPreview chat;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final fallbackLetter = chat.displayName.trim().isEmpty
        ? '?'
        : chat.displayName.trim().characters.first.toUpperCase();
    return Card(
      child: ListTile(
        onTap: () => context.push(
          Uri(
            path: '/chats/${chat.conversationId}',
            queryParameters: {
              'friendId': chat.friendId,
              'name': chat.displayName,
            },
          ).toString(),
        ),
        leading: CircleAvatar(
          backgroundColor: primary.withValues(alpha: 0.12),
          foregroundImage: chat.avatarUrl == null
              ? null
              : NetworkImage(chat.avatarUrl!),
          child: chat.avatarUrl == null ? Text(fallbackLetter) : null,
        ),
        title: Text(chat.displayName),
        subtitle: Text('@${chat.username}'),
        trailing: Icon(Remix.arrow_right_s_line, color: primary),
      ),
    );
  }
}

class _ChatEmptyState extends StatelessWidget {
  const _ChatEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return ListView(
      padding: ContentLayout.pagePadding,
      children: [
        ContentLayout.widthBox(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(icon, size: 42, color: primary),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(message, textAlign: TextAlign.center),
                  if (action != null) ...[const SizedBox(height: 12), action!],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
