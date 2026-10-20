import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lumii_quest/features/me/presentation/me_page.dart';
import 'package:lumii_quest/features/profile/presentation/public_profile_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// "Me" tab: shows the signed-in user's own profile, or the sign-in form.
class OwnProfilePage extends StatefulWidget {
  const OwnProfilePage({super.key});

  @override
  State<OwnProfilePage> createState() => _OwnProfilePageState();
}

class _OwnProfilePageState extends State<OwnProfilePage> {
  late final StreamSubscription<AuthState> _authSubscription;
  int _reloadCount = 0;

  @override
  void initState() {
    super.initState();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      _,
    ) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  Future<void> _edit() async {
    await context.push<bool>('/edit-profile');
    if (mounted) setState(() => _reloadCount++);
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final username = user?.userMetadata?['username'];
    if (user == null || username is! String || username.isEmpty) {
      return const MePage();
    }

    return PublicProfilePage(
      key: ValueKey('$username-$_reloadCount'),
      username: username,
      embedded: true,
      onEdit: _edit,
    );
  }
}
