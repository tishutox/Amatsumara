import 'dart:convert';

enum ChatMessageKind { text, image, audio, gallery }

class ChatImageItem {
  const ChatImageItem({required this.url, this.aspectRatio = 0});

  final String url;

  /// width / height. 0 means unknown. > 1 is landscape, < 1 is portrait.
  final double aspectRatio;

  bool get isLandscape => aspectRatio > 1.0;

  Map<String, dynamic> toJson() => {'url': url, 'aspect': aspectRatio};

  factory ChatImageItem.fromJson(Map<String, dynamic> json) => ChatImageItem(
    url: json['url'] as String? ?? '',
    aspectRatio: (json['aspect'] as num?)?.toDouble() ?? 0,
  );
}

/// Plaintext that gets encrypted and stored inside a chat message.
///
/// Text messages stay plain strings for backward compatibility. Image, audio
/// and gallery messages are encoded as a small JSON envelope so the bubble can
/// render them.
class ChatMessageContent {
  const ChatMessageContent._({
    required this.kind,
    this.text,
    this.url,
    this.name,
    this.duration,
    this.images,
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

  factory ChatMessageContent.gallery(List<ChatImageItem> images) =>
      ChatMessageContent._(kind: ChatMessageKind.gallery, images: images);

  final ChatMessageKind kind;
  final String? text;
  final String? url;
  final String? name;
  final double? duration;
  final List<ChatImageItem>? images;

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
    ChatMessageKind.gallery => jsonEncode({
      'type': 'gallery',
      'images': [for (final image in images ?? const <ChatImageItem>[]) image.toJson()],
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
          if (type == 'gallery') {
            final rawImages = decoded['images'];
            if (rawImages is List) {
              final images = rawImages
                  .whereType<Map>()
                  .map(
                    (e) => ChatImageItem.fromJson(
                      Map<String, dynamic>.from(e),
                    ),
                  )
                  .where((image) => image.url.isNotEmpty)
                  .toList();
              if (images.isNotEmpty) {
                return ChatMessageContent.gallery(images);
              }
            }
          }
        }
      } catch (_) {
        // Fall through to text.
      }
    }
    return ChatMessageContent.text(raw);
  }
}
