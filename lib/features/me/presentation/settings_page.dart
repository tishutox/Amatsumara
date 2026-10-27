import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumii_quest/core/responsive/content_layout.dart';
import 'package:lumii_quest/features/account/data/account_repository.dart';
import 'package:lumii_quest/features/profile/data/profile_repository.dart';
import 'package:lumii_quest/features/profile/domain/user_profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final StreamSubscription<AuthState> _authSubscription;
  UserProfile? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      state,
    ) {
      if (mounted && state.event == AuthChangeEvent.signedOut) {
        context.go('/');
      }
    });
    _load();
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final profile = await ProfileRepository().getById(user.id);
      if (mounted) {
        setState(() {
          _profile = profile;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editProfile() async {
    await context.push<bool>('/edit-profile');
    if (mounted) _load();
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
  }

  String get _username {
    final metadata = Supabase.instance.client.auth.currentUser?.userMetadata;
    final raw = metadata?['username'];
    final metaValue = raw is String && raw.isNotEmpty ? raw : null;
    return _profile?.username ?? metaValue ?? '';
  }

  String get _displayName {
    final metadata = Supabase.instance.client.auth.currentUser?.userMetadata;
    final raw = metadata?['display_name'];
    final metaValue = raw is String && raw.isNotEmpty ? raw : null;
    return _profile?.displayName ?? metaValue ?? '';
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _changePassword() async {
    final email = Supabase.instance.client.auth.currentUser?.email;
    if (email == null || email.isEmpty) {
      _showSnackBar('No email address is linked to this account.');
      return;
    }
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      _showSnackBar('A password reset link has been sent to your email.');
    } catch (error) {
      _showSnackBar('Password reset could not be sent: $error');
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently deletes your account, profile, friendships, notifications and chats. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(LucideIcons.trash),
            label: const Text('Delete account'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await AccountRepository().deleteCurrentAccount();
      _showSnackBar('Your account has been deleted.');
    } catch (error) {
      _showSnackBar('Account could not be deleted: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
          icon: const Icon(LucideIcons.chevronLeft),
        ),
      ),
      body: ListView(
        padding: ContentLayout.pagePadding,
        children: [
          if (user != null) ...[
            ContentLayout.widthBox(child: _buildHeader(user)),
            ContentLayout.sectionGap,
          ],
          if (user != null) ...[
            ContentLayout.widthBox(
              child: _SettingsSection(
                title: 'Kontoinformationen',
                children: [
                  _SettingsValueTile(
                    icon: LucideIcons.atSign,
                    label: 'Username',
                    value: _username,
                  ),
                  _SettingsValueTile(
                    icon: LucideIcons.userRound,
                    label: 'Displayname',
                    value: _displayName,
                  ),
                  _SettingsValueTile(
                    icon: LucideIcons.mail,
                    label: 'Email',
                    value: user.email ?? '',
                  ),
                ],
              ),
            ),
            ContentLayout.sectionGap,
            ContentLayout.widthBox(
              child: _SettingsSection(
                title: 'Danger Zone',
                children: [
                  _SettingsValueTile(
                    icon: LucideIcons.keyRound,
                    label: 'Change Password',
                    onTap: _changePassword,
                  ),
                  _SettingsValueTile(
                    icon: LucideIcons.trash2,
                    label: 'Delete Account',
                    labelColor: Theme.of(context).colorScheme.error,
                    onTap: _deleteAccount,
                  ),
                ],
              ),
            ),
            ContentLayout.sectionGap,
          ],
          ContentLayout.widthBox(
            child: const _SettingsSection(
              title: 'App Settings',
              children: [
                _SettingsTile(
                  icon: LucideIcons.languages,
                  label: 'Language & Region',
                ),
                _SettingsTile(icon: LucideIcons.bell, label: 'Notifications'),
                _SettingsTile(
                  icon: LucideIcons.accessibility,
                  label: 'Accessibility',
                ),
                _SettingsTile(icon: LucideIcons.heart, label: 'Interests'),
              ],
            ),
          ),
          ContentLayout.sectionGap,
          ContentLayout.widthBox(
            child: const _SettingsSection(
              title: 'Support',
              children: [
                _SettingsTile(
                  icon: LucideIcons.lifeBuoy,
                  label: 'Support Center',
                ),
                _SettingsTile(
                  icon: LucideIcons.messageSquareText,
                  label: 'Share Feedback',
                ),
              ],
            ),
          ),
          if (user != null) ...[
            const SizedBox(height: 24),
            ContentLayout.widthBox(
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _signOut,
                  icon: const Icon(LucideIcons.logOut),
                  label: const Text('Sign Out'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(User user) {
    if (_loading) {
      return const Card(
        child: SizedBox(
          height: 200,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final rawDisplayName = metadata['display_name'];
    final metadataDisplayName = rawDisplayName is String &&
            rawDisplayName.isNotEmpty
        ? rawDisplayName
        : null;
    final rawAvatar = metadata['avatar_url'];
    final metadataAvatar = rawAvatar is String && rawAvatar.isNotEmpty
        ? rawAvatar
        : null;

    return _ProfileHeader(
      displayName:
          _profile?.displayName ?? metadataDisplayName ?? 'Lumii Quest member',
      email: user.email ?? '',
      avatarUrl: _profile?.avatarUrl ?? metadataAvatar,
      bannerUrl: _profile?.bannerUrl,
      onEdit: _editProfile,
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.displayName,
    required this.email,
    required this.onEdit,
    this.avatarUrl,
    this.bannerUrl,
  });

  final String displayName;
  final String email;
  final String? avatarUrl;
  final String? bannerUrl;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final surface = theme.colorScheme.surface;
    final onSurface = theme.colorScheme.onSurface;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              AspectRatio(aspectRatio: 3, child: _banner(primary)),
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: surface.withValues(alpha: 0.92),
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: 'Edit profile',
                    onPressed: onEdit,
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    icon: Icon(LucideIcons.pencilRuler, color: primary),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Transform.translate(
                  offset: const Offset(0, -24),
                  child: _avatar(primary, surface),
                ),
                Text(
                  displayName,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    email,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: onSurface.withValues(alpha: 0.62),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _banner(Color primary) {
    final placeholder = Center(
      child: Icon(LucideIcons.image, size: 36, color: primary),
    );
    return ColoredBox(
      color: primary.withValues(alpha: 0.16),
      child: bannerUrl == null
          ? placeholder
          : Image.network(
              bannerUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }

  Widget _avatar(Color primary, Color surface) {
    final fallback = ColoredBox(
      color: primary.withValues(alpha: 0.16),
      child: Center(
        child: Text(
          displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
          style: TextStyle(
            color: primary,
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
    return SizedBox.square(
      dimension: 72,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: surface, shape: BoxShape.circle),
        child: ClipOval(
          child: avatarUrl == null
              ? fallback
              : Image.network(
                  avatarUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => fallback,
                ),
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  const Divider(height: 1, indent: 56, endIndent: 16),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return ListTile(
      leading: Icon(icon, color: primary),
      title: Text(label),
      trailing: Icon(LucideIcons.chevronRight, color: primary),
    );
  }
}

class _SettingsValueTile extends StatelessWidget {
  const _SettingsValueTile({
    required this.icon,
    required this.label,
    this.value,
    this.labelColor,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? value;
  final Color? labelColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.62);
    final accent = labelColor ?? primary;
    return ListTile(
      leading: Icon(icon, color: accent),
      title: Text(label, style: TextStyle(color: labelColor)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null && value!.isNotEmpty) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                value!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: muted, fontSize: 14),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Icon(LucideIcons.chevronRight, color: accent, size: 20),
        ],
      ),
      onTap: onTap,
    );
  }
}
