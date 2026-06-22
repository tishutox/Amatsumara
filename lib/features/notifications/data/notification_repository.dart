import 'package:lumii_quest/features/notifications/domain/notification_item.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationRepository {
  NotificationRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<NotificationItem>> getRecent() async {
    final user = _client.auth.currentUser;
    if (user == null) return const [];

    final rows = await _client
        .from('notifications')
        .select(
          'id,title,body,created_at,is_read,kind,action_status,friend_request_id',
        )
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .limit(100);

    return rows
        .map(
          (row) => NotificationItem(
            id: row['id'] as int,
            title: row['title'] as String,
            body: row['body'] as String,
            createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
            isRead: row['is_read'] as bool? ?? false,
            kind: row['kind'] as String? ?? 'general',
            actionStatus: row['action_status'] as String? ?? 'none',
            friendRequestId: row['friend_request_id'] as int?,
          ),
        )
        .toList();
  }

  Future<void> respondToFriendRequest({
    required int requestId,
    required bool accept,
  }) async {
    await _client.rpc(
      'respond_to_friend_request',
      params: {
        'p_request_id': requestId,
        'p_response': accept ? 'accepted' : 'declined',
      },
    );
  }
}
