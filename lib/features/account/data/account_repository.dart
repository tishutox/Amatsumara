import 'package:supabase_flutter/supabase_flutter.dart';

class AccountRepository {
  AccountRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<void> deleteCurrentAccount() async {
    await _client.rpc('delete_own_account');
    try {
      await _client.auth.signOut();
    } catch (_) {
      // The auth user may already be gone after the RPC; in that case the
      // server-side account deletion succeeded and the local session will be
      // invalidated on the next auth refresh/app start.
    }
  }

  Future<void> updateUsername(String username) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to update your username.');
    }
    await _client
        .from('profiles')
        .update({'username': username})
        .eq('id', user.id);
  }

  Future<void> updateDisplayName(String displayName) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to update your display name.');
    }
    await _client
        .from('profiles')
        .update({'display_name': displayName})
        .eq('id', user.id);
    await _client.auth.updateUser(
      UserAttributes(data: {'display_name': displayName}),
    );
  }

  Future<void> updateEmail(String email) async {
    await _client.auth.updateUser(UserAttributes(email: email));
  }

  Future<void> updatePassword(String newPassword) async {
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }
}
