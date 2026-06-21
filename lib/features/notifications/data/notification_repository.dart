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
        .select('id,title,body,created_at,is_read')
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
          ),
        )
        .toList();
  }
}
