import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.encryptedPayload,
    required this.sentAt,
    this.senderDeviceId,
  });

  final int id;
  final String conversationId;
  final String senderId;
  final String? senderDeviceId;
  final Map<String, dynamic> encryptedPayload;
  final DateTime sentAt;

  factory ChatMessage.fromDatabase(Map<String, dynamic> row) {
    return ChatMessage(
      id: row['id'] as int,
      conversationId: row['conversation_id'] as String,
      senderId: row['sender_id'] as String,
      senderDeviceId: row['sender_device_id'] as String?,
      encryptedPayload: Map<String, dynamic>.from(row['encrypted_payload']),
      sentAt:
          DateTime.tryParse(row['sent_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

class ChatDeviceKey {
  const ChatDeviceKey({
    required this.userId,
    required this.deviceId,
    required this.publicKey,
    required this.deviceName,
  });

  final String userId;
  final String deviceId;
  final String publicKey;
  final String deviceName;

  factory ChatDeviceKey.fromDatabase(Map<String, dynamic> row) {
    return ChatDeviceKey(
      userId: row['user_id'] as String,
      deviceId: row['device_id'] as String,
      publicKey: row['public_key'] as String,
      deviceName: row['device_name'] as String? ?? 'Lumii device',
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

  Future<void> upsertDeviceKey({
    required String deviceId,
    required String publicKey,
    required String deviceName,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return;
    }
    await _client.from('chat_device_keys').upsert({
      'user_id': user.id,
      'device_id': deviceId,
      'device_name': deviceName,
      'public_key': publicKey,
      'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      'revoked_at': null,
    });
  }

  Future<List<ChatDeviceKey>> listActiveDeviceKeys(
    Iterable<String> userIds,
  ) async {
    final ids = userIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) {
      return const [];
    }
    final rows = await _client.rpc(
      'list_chat_device_keys',
      params: {'p_user_ids': ids},
    );
    return (rows as List)
        .map(
          (row) => ChatDeviceKey.fromDatabase(Map<String, dynamic>.from(row)),
        )
        .toList();
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
    final userId = _client.auth.currentUser?.id;
    var query = _client
        .from('chat_messages')
        .select(
          'id,conversation_id,sender_id,sender_device_id,encrypted_payload,sent_at',
        )
        .eq('conversation_id', conversationId);
    if (userId != null) {
      query = query.not('deleted_for', 'cs', [userId]);
    }
    final rows = await query.order('sent_at', ascending: true);
    return (rows as List)
        .map((row) => ChatMessage.fromDatabase(Map<String, dynamic>.from(row)))
        .toList();
  }

  Stream<List<ChatMessage>> watchMessages(String conversationId) {
    final userId = _client.auth.currentUser?.id;
    return _client
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('sent_at', ascending: true)
        .map(
          (rows) => rows
              .where(
                (row) =>
                    userId == null ||
                    row['deleted_for'] is! List ||
                    !(row['deleted_for'] as List).contains(userId),
              )
              .map(
                (row) =>
                    ChatMessage.fromDatabase(Map<String, dynamic>.from(row)),
              )
              .toList(),
        );
  }

  Future<void> deleteMessageForAll(int messageId) async {
    await _client.rpc(
      'delete_chat_message_for_all',
      params: {'p_message_id': messageId},
    );
  }

  Future<void> deleteMessageForMe(int messageId) async {
    await _client.rpc(
      'delete_chat_message_for_me',
      params: {'p_message_id': messageId},
    );
  }

  Future<Map<String, dynamic>?> fetchFriendProfile(String friendId) async {
    return _client
        .from('profiles')
        .select('username,display_name,avatar_url')
        .eq('id', friendId)
        .maybeSingle();
  }

  Future<void> sendMessage({
    required String conversationId,
    required String senderDeviceId,
    required Map<String, dynamic> encryptedPayload,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to send a message.');
    }
    await _client.from('chat_messages').insert({
      'conversation_id': conversationId,
      'sender_id': user.id,
      'sender_device_id': senderDeviceId,
      'encrypted_payload': encryptedPayload,
    });
  }

  Future<String> uploadChatMedia({
    required Uint8List bytes,
    required String extension,
    required String contentType,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to send media.');
    }
    final path =
        '${user.id}/${DateTime.now().millisecondsSinceEpoch}.$extension';
    await _client.storage.from('chat-media').uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(contentType: contentType),
    );
    return _client.storage.from('chat-media').getPublicUrl(path);
  }
}
