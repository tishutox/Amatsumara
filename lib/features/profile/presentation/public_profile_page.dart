import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lumii_quest/core/icons/app_icons.dart';
import 'package:lumii_quest/features/profile/data/profile_repository.dart';
import 'package:lumii_quest/features/profile/domain/user_profile.dart';

/// Public profile view reachable via the `lumiiquest://u/<username>` deep link.
class PublicProfilePage extends StatefulWidget {
  const PublicProfilePage({super.key, required this.username});

  final String username;

  @override
  State<PublicProfilePage> createState() => _PublicProfilePageState();
}

class _PublicProfilePageState extends State<PublicProfilePage> {
  final _repository = ProfileRepository();
  UserProfile? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await _repository.getByUsername(widget.username);
    if (mounted) {
      setState(() {
        _profile = profile;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
          icon: const AppIcon(AppIcons.chevronLeft),
        ),
        title: Text(widget.username),
        surfaceTintColor: Colors.transparent,
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final profile = _profile;
    if (profile == null) {
      return const Center(child: Text('Profile not found.'));
    }
    final avatarUrl = profile.avatarUrl;
    return Center(
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
              profile.displayName,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '@${profile.username}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF8E8E93),
              ),
            ),
            if (profile.bio.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(profile.bio, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}
