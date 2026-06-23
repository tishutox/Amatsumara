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
}
