import 'package:supabase_flutter/supabase_flutter.dart';

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.encryptedPayload,
    required this.sentAt,
  });

  final int id;
  final String conversationId;
  final String senderId;
  final Map<String, dynamic> encryptedPayload;
  final DateTime sentAt;

  factory ChatMessage.fromDatabase(Map<String, dynamic> row) {
    return ChatMessage(
      id: row['id'] as int,
      conversationId: row['conversation_id'] as String,
      senderId: row['sender_id'] as String,
      encryptedPayload: Map<String, dynamic>.from(row['encrypted_payload']),
      sentAt:
          DateTime.tryParse(row['sent_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

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

  Future<void> upsertIdentityKey(String publicKey) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return;
    }
    await _client.from('chat_identity_keys').upsert({
      'user_id': user.id,
      'public_key': publicKey,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<String?> getPublicKey(String userId) async {
    final row = await _client
        .from('chat_identity_keys')
        .select('public_key')
        .eq('user_id', userId)
        .maybeSingle();
    return row?['public_key'] as String?;
  }

  Future<List<ChatMessage>> listMessages(String conversationId) async {
    final rows = await _client
        .from('chat_messages')
        .select('id,conversation_id,sender_id,encrypted_payload,sent_at')
        .eq('conversation_id', conversationId)
        .order('sent_at');
    return (rows as List)
        .map((row) => ChatMessage.fromDatabase(Map<String, dynamic>.from(row)))
        .toList();
  }

  Stream<List<ChatMessage>> watchMessages(String conversationId) {
    return _client
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('sent_at')
        .map(
          (rows) => rows
              .map(
                (row) =>
                    ChatMessage.fromDatabase(Map<String, dynamic>.from(row)),
              )
              .toList(),
        );
  }

  Future<void> sendMessage({
    required String conversationId,
    required Map<String, dynamic> encryptedPayload,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to send a message.');
    }
    await _client.from('chat_messages').insert({
      'conversation_id': conversationId,
      'sender_id': user.id,
      'encrypted_payload': encryptedPayload,
    });
  }
}
