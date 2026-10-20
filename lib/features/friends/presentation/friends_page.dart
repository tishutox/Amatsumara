import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lumii_quest/core/responsive/content_layout.dart';
import 'package:lumii_quest/features/friends/data/friend_repository.dart';
import 'package:lumii_quest/features/friends/domain/friend_summary.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  final _repository = FriendRepository();
  late Future<List<FriendSummary>> _friendsFuture;
  FriendSortField _sortField = FriendSortField.username;
  FriendSortDirection _sortDirection = FriendSortDirection.ascending;

  @override
  void initState() {
    super.initState();
    _friendsFuture = _repository.listFriends();
  }

  void _reload() {
    setState(() => _friendsFuture = _repository.listFriends());
  }

  Future<void> _refresh() async {
    final future = _repository.listFriends();
    setState(() => _friendsFuture = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        final themedPrimary = Theme.of(context).colorScheme.primary;
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Back',
              onPressed: () => context.pop(),
              icon: const Icon(LucideIcons.chevronLeft),
            ),
            title: const Text('Friends'),
            foregroundColor: themedPrimary,
            surfaceTintColor: Colors.transparent,
            actions: [
              IconButton(
                tooltip: 'Refresh',
                onPressed: _refresh,
                icon: const Icon(LucideIcons.refreshCcw),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _refresh,
            child: _FriendsBody(
              friendsFuture: _friendsFuture,
              sortField: _sortField,
              sortDirection: _sortDirection,
              onSortFieldChanged: (value) => setState(() => _sortField = value),
              onSortDirectionChanged: (value) =>
                  setState(() => _sortDirection = value),
              onReload: _reload,
            ),
          ),
        );
      },
    );
  }
}

class _FriendsBody extends StatelessWidget {
  const _FriendsBody({
    required this.friendsFuture,
    required this.sortField,
    required this.sortDirection,
    required this.onSortFieldChanged,
    required this.onSortDirectionChanged,
    required this.onReload,
  });

  final Future<List<FriendSummary>> friendsFuture;
  final FriendSortField sortField;
  final FriendSortDirection sortDirection;
  final ValueChanged<FriendSortField> onSortFieldChanged;
  final ValueChanged<FriendSortDirection> onSortDirectionChanged;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: ContentLayout.pagePadding,
      children: [
        ContentLayout.widthBox(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DropdownButton<FriendSortField>(
                    value: sortField,
                    icon: const Icon(LucideIcons.chevronDown),
                    borderRadius: BorderRadius.circular(14),
                    onChanged: (value) {
                      if (value != null) {
                        onSortFieldChanged(value);
                      }
                    },
                    items: FriendSortField.values
                        .map(
                          (field) => DropdownMenuItem(
                            value: field,
                            child: Text('Sort by ${field.label}'),
                          ),
                        )
                        .toList(),
                  ),
                  DropdownButton<FriendSortDirection>(
                    value: sortDirection,
                    icon: const Icon(LucideIcons.chevronDown),
                    borderRadius: BorderRadius.circular(14),
                    onChanged: (value) {
                      if (value != null) {
                        onSortDirectionChanged(value);
                      }
                    },
                    items: FriendSortDirection.values
                        .map(
                          (direction) => DropdownMenuItem(
                            value: direction,
                            child: Text(direction.label),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
        ),
        ContentLayout.sectionGap,
        FutureBuilder<List<FriendSummary>>(
          future: friendsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _EmptyFriendsState(
                icon: LucideIcons.triangleAlert,
                message: 'Friends could not be loaded.',
                action: TextButton.icon(
                  onPressed: onReload,
                  icon: const Icon(LucideIcons.refreshCcw),
                  label: const Text('Try again'),
                ),
              );
            }

            final friends = sortFriends(
              snapshot.data ?? const [],
              field: sortField,
              direction: sortDirection,
            );
            if (friends.isEmpty) {
              return const _EmptyFriendsState(
                icon: LucideIcons.bookHeart,
                message:
                    'No friends yet. Friend requests will appear from profiles and notifications.',
              );
            }

            return Column(
              children: [
                for (final friend in friends) ...[
                  ContentLayout.widthBox(child: _FriendTile(friend: friend)),
                  ContentLayout.sectionGap,
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _FriendTile extends StatelessWidget {
  const _FriendTile({required this.friend});

  final FriendSummary friend;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final fallbackLetter = friend.displayName.trim().isEmpty
        ? '?'
        : friend.displayName.trim().characters.first.toUpperCase();
    return Card(
      child: ListTile(
        onTap: () => context.push('/u/${friend.username}'),
        leading: CircleAvatar(
          backgroundColor: primary.withValues(alpha: 0.12),
          foregroundImage: friend.avatarUrl == null
              ? null
              : NetworkImage(friend.avatarUrl!),
          child: friend.avatarUrl == null ? Text(fallbackLetter) : null,
        ),
        title: Text(friend.displayName),
        subtitle: Text('@${friend.username}'),
        trailing: Icon(LucideIcons.chevronRight, color: primary),
      ),
    );
  }
}

class _EmptyFriendsState extends StatelessWidget {
  const _EmptyFriendsState({
    required this.icon,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return ContentLayout.widthBox(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(icon, size: 42, color: primary),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              if (action != null) ...[const SizedBox(height: 12), action!],
            ],
          ),
        ),
      ),
    );
  }
}
