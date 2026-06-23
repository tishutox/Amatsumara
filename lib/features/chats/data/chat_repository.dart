import 'package:supabase_flutter/supabase_flutter.dart';

class ChatPreview {
  const ChatPreview({
    required this.conversationId,
    required this.friendId,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.lastMessageAt,
  });

  final String conversationId;
  final String friendId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final DateTime? lastMessageAt;

  factory ChatPreview.fromDatabase(Map<String, dynamic> row) {
    return ChatPreview(
      conversationId: row['conversation_id'] as String,
      friendId: row['friend_id'] as String,
      username: row['username'] as String? ?? '',
      displayName: row['display_name'] as String? ?? 'Lumii Quest member',
      avatarUrl: row['avatar_url'] as String?,
      lastMessageAt: DateTime.tryParse(row['last_message_at'] as String? ?? ''),
    );
  }
}

class ChatRepository {
  ChatRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<ChatPreview>> listChats() async {
    if (_client.auth.currentUser == null) {
      return const [];
    }
    final rows = await _client.rpc('list_my_chats');
    return (rows as List)
        .map((row) => ChatPreview.fromDatabase(Map<String, dynamic>.from(row)))
        .toList();
  }
}
