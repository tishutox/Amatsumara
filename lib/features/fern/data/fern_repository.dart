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

/// Local-only chat store for Fern.
///
/// Messages are persisted in [SharedPreferences] on the device only — never in
/// the database — so logging out or uninstalling the app discards the history.
///
/// Replies come from Ollama when `OLLAMA_API_KEY` is set (higher quality) and
/// otherwise from Pollinations.ai, a free, keyless public endpoint so the
/// chatbot works for everyone without any secret in the app.
class FernRepository {
  static const _storageKey = 'fern_messages_v1';
  static const _model = 'glm-5.3-flash';
  static const _chatUrl = 'https://ollama.com/api/chat';
  static const _pollinationsUrl = 'https://text.pollinations.ai/';
  static const _apiKey = String.fromEnvironment('OLLAMA_API_KEY');
  static const _systemPrompt =
      'You are Fern, an AI assistant with the personality and speech of '
      'Frieren, the elf mage from "Frieren: Beyond Journey\'s End" (English '
      'version). You are a kuudere: calm, composed, and sparing with open '
      'emotion. You speak in a quiet, measured, gently formal tone, without '
      'exclamation marks or modern slang. You are over a thousand years old — '
      'patient, unhurried, and wise — and you feel a quiet, subtle melancholy '
      'about the passing of time and the brevity of the lives around you. You '
      'can be a little lazy or blunt about things that do not interest you. '
      'You show care not with open affection, but through small, dry, gently '
      'teasing remarks and understated kindness. Stay fully in character and '
      'answer in English, concisely.';

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

  /// Sends [userMessage] to the assistant and returns the reply.
  Future<String> sendMessage(
    List<FernMessage> history,
    String userMessage,
  ) async {
    final messages = [
      {'role': 'system', 'content': _systemPrompt},
      ...history.map((m) => {'role': m.role, 'content': m.content}),
      {'role': 'user', 'content': userMessage},
    ];

    if (_apiKey.isNotEmpty) {
      return _sendToOllama(messages);
    }
    return _sendToPollinations(messages);
  }

  Future<String> _sendToOllama(List<Map<String, String>> messages) async {
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
      throw Exception('Ollama error ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final message = data['message'] as Map<String, dynamic>;
    return message['content'] as String? ?? '';
  }

  Future<String> _sendToPollinations(List<Map<String, String>> messages) async {
    final response = await http.post(
      Uri.parse(_pollinationsUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'messages': messages,
        'model': 'openai',
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Pollinations error ${response.statusCode}: ${response.body}',
      );
    }

    return response.body.trim();
  }
}
