import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// A single message in the local Fern (AI assistant) conversation.
class FernMessage {
  const FernMessage({
    required this.role,
    required this.content,
    required this.sentAt,
  });

  final String role; // 'user' or 'assistant'
  final String content;
  final DateTime sentAt;

  Map<String, dynamic> toJson() => {
    'role': role,
    'content': content,
    'sentAt': sentAt.toIso8601String(),
  };

  factory FernMessage.fromJson(Map<String, dynamic> json) => FernMessage(
    role: json['role'] as String? ?? 'assistant',
    content: json['content'] as String? ?? '',
    sentAt:
        DateTime.tryParse(json['sentAt'] as String? ?? '') ?? DateTime.now(),
  );
}

/// Local-only chat store for Fern, backed by the Ollama cloud API.
///
/// Messages are persisted in [SharedPreferences] on the device only — never in
/// the database — so logging out or uninstalling the app discards the history.
class FernRepository {
  static const _storageKey = 'fern_messages_v1';
  static const _model = 'glm-5.3-flash';
  static const _chatUrl = 'https://ollama.com/api/chat';
  static const _apiKey = String.fromEnvironment('OLLAMA_API_KEY');

  Future<List<FernMessage>> loadMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .map((e) => FernMessage.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveMessages(List<FernMessage> messages) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(messages.map((m) => m.toJson()).toList()),
    );
  }

  Future<void> clearMessages() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  /// Sends [userMessage] to Ollama and returns the assistant reply.
  Future<String> sendMessage(
    List<FernMessage> history,
    String userMessage,
  ) async {
    if (_apiKey.isEmpty) {
      throw StateError(
        'OLLAMA_API_KEY is not set. Pass it at build time with '
        '--dart-define=OLLAMA_API_KEY=...',
      );
    }

    final messages = [
      ...history.map((m) => {'role': m.role, 'content': m.content}),
      {'role': 'user', 'content': userMessage},
    ];

    final response = await http.post(
      Uri.parse(_chatUrl),
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': _model,
        'messages': messages,
        'stream': false,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Ollama error ${response.statusCode}: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final message = data['message'] as Map<String, dynamic>;
    return message['content'] as String? ?? '';
  }
}
