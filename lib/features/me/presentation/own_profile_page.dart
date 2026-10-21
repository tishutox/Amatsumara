import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lumii_quest/features/me/presentation/me_page.dart';
import 'package:lumii_quest/features/profile/presentation/public_profile_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// "Me" tab: shows the signed-in user's own profile, or the sign-in form.
class OwnProfilePage extends StatefulWidget {
  const OwnProfilePage({this.reloadCount = 0, super.key});

  final int reloadCount;

  @override
  State<OwnProfilePage> createState() => _OwnProfilePageState();
}

class _OwnProfilePageState extends State<OwnProfilePage> {
  late final StreamSubscription<AuthState> _authSubscription;

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

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final username = user?.userMetadata?['username'];
    if (user == null || username is! String || username.isEmpty) {
      return const MePage();
    }

    return PublicProfilePage(
      key: ValueKey('$username-${widget.reloadCount}'),
      username: username,
      embedded: true,
    );
  }
}
