import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lumii_quest/core/icons/app_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The signed-in user's own profile, with Edit and copy-link actions.
class OwnProfilePage extends StatelessWidget {
  const OwnProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final metadata = user?.userMetadata ?? const <String, dynamic>{};
    final displayName = metadata['display_name'] as String? ?? '';
    final username = metadata['username'] as String? ?? '';
    final email = user?.email ?? '';
    final avatarUrl = metadata['avatar_url'] as String?;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => context.pop(),
          icon: const AppIcon(AppIcons.chevronLeft),
        ),
        title: Text(displayName.isEmpty ? 'Profile' : displayName),
        actions: [
          IconButton(
            tooltip: 'Copy profile link',
            onPressed: () => _copyProfileLink(context, username),
            icon: const AppIcon(AppIcons.link),
          ),
          IconButton(
            tooltip: 'Edit profile',
            onPressed: () => context.push('/edit-profile'),
            icon: const AppIcon(AppIcons.pencilRuler),
          ),
        ],
        surfaceTintColor: Colors.transparent,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 44,
                backgroundColor: const Color(0xFFE4E4E8),
                backgroundImage: (avatarUrl == null || avatarUrl.isEmpty)
                    ? null
                    : NetworkImage(avatarUrl),
                child: (avatarUrl == null || avatarUrl.isEmpty)
                    ? const AppIcon(AppIcons.circleUserRound, size: 40)
                    : null,
              ),
              const SizedBox(height: 16),
              Text(
                displayName.isEmpty ? 'Profile' : displayName,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (username.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '@$username',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF8E8E93),
                  ),
                ),
              ],
              if (email.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  email,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF8E8E93),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copyProfileLink(BuildContext context, String username) async {
    await Clipboard.setData(
      ClipboardData(text: 'lumiiquest://u/$username'),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile link copied.')));
    }
  }
}
