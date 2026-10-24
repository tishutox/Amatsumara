import 'dart:convert';

enum ChatMessageKind { text, image, audio }

/// Plaintext that gets encrypted and stored inside a chat message.
///
/// Text messages stay plain strings for backward compatibility. Image and
/// audio messages are encoded as a small JSON envelope so the bubble can
/// render them.
class ChatMessageContent {
  const ChatMessageContent._({
    required this.kind,
    this.text,
    this.url,
    this.name,
    this.duration,
  });

  factory ChatMessageContent.text(String text) =>
      ChatMessageContent._(kind: ChatMessageKind.text, text: text);

  factory ChatMessageContent.image({required String url, String name = ''}) =>
      ChatMessageContent._(kind: ChatMessageKind.image, url: url, name: name);

  factory ChatMessageContent.audio({
    required String url,
    required double duration,
  }) => ChatMessageContent._(
    kind: ChatMessageKind.audio,
    url: url,
    duration: duration,
  );

  final ChatMessageKind kind;
  final String? text;
  final String? url;
  final String? name;
  final double? duration;

  String encode() => switch (kind) {
    ChatMessageKind.text => text ?? '',
    ChatMessageKind.image => jsonEncode({
      'type': 'image',
      'url': url,
      'name': name ?? '',
    }),
    ChatMessageKind.audio => jsonEncode({
      'type': 'audio',
      'url': url,
      'duration': duration ?? 0,
    }),
  };

  static ChatMessageContent decode(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('{')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) {
          final type = decoded['type'];
          final url = decoded['url'];
          if (type == 'image' && url is String && url.isNotEmpty) {
            return ChatMessageContent.image(
              url: url,
              name: (decoded['name'] as String?) ?? '',
            );
          }
          if (type == 'audio' && url is String && url.isNotEmpty) {
            final duration = decoded['duration'];
            return ChatMessageContent.audio(
              url: url,
              duration: duration is num ? duration.toDouble() : 0,
            );
          }
        }
      } catch (_) {
        // Fall through to text.
      }
    }
    return ChatMessageContent.text(raw);
  }
}
