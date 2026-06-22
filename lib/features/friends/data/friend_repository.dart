import 'package:lumii_quest/features/friends/domain/relationship_status.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FriendRepository {
  FriendRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<RelationshipStatus> getStatus(String targetUserId) async {
    if (_client.auth.currentUser == null) return RelationshipStatus.signedOut;
    final result = await _client.rpc(
      'get_relationship_status',
      params: {'p_target_user_id': targetUserId},
    );
    return RelationshipStatus.fromDatabase(result as String?);
  }

  Future<void> sendRequest(String targetUserId) async {
    await _client.rpc(
      'send_friend_request',
      params: {'p_target_user_id': targetUserId},
    );
  }

  Future<void> unfriend(String targetUserId) async {
    await _client.rpc(
      'unfriend_user',
      params: {'p_target_user_id': targetUserId},
    );
  }
}
