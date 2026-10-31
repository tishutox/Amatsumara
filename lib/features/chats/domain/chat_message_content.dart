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

/// Metadata shown above a reply bubble so the recipient knows which message
/// it is answering. It is stored encrypted inside the message payload.
class ChatReplyQuote {
  const ChatReplyQuote({
    required this.messageId,
    required this.senderName,
    required this.preview,
  });

  final int messageId;
  final String senderName;
  final String preview;

  Map<String, dynamic> toJson() => {
    'messageId': messageId,
    'senderName': senderName,
    'preview': preview,
  };

  factory ChatReplyQuote.fromJson(Map<String, dynamic> json) => ChatReplyQuote(
    messageId: (json['messageId'] as num?)?.toInt() ?? 0,
    senderName: json['senderName'] as String? ?? '',
    preview: json['preview'] as String? ?? '',
  );
}

/// Plaintext that gets encrypted and stored inside a chat message.
///
/// Text messages stay plain strings for backward compatibility. Image, audio
/// and gallery messages are encoded as a small JSON envelope so the bubble can
/// render them. Replies add a `reply_to` envelope around any kind.
class ChatMessageContent {
  const ChatMessageContent._({
    required this.kind,
    this.text,
    this.url,
    this.name,
    this.duration,
    this.images,
    this.replyTo,
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
  final ChatReplyQuote? replyTo;

  ChatMessageContent withReply(ChatReplyQuote? replyTo) => ChatMessageContent._(
    kind: kind,
    text: text,
    url: url,
    name: name,
    duration: duration,
    images: images,
    replyTo: replyTo,
  );

  /// Short human-readable summary used in reply quotes and forward previews.
  String get preview => switch (kind) {
    ChatMessageKind.text => _ellipsis((text ?? '').replaceAll('\n', ' ')),
    ChatMessageKind.image => 'Photo',
    ChatMessageKind.audio => 'Voice message',
    ChatMessageKind.gallery => '${images?.length ?? 0} photo${(images?.length ?? 0) == 1 ? '' : 's'}',
  };

  static String _ellipsis(String value) =>
      value.length > 60 ? '${value.substring(0, 60)}Ã¢â‚¬Â¦' : value;

  String encode() {
    if (replyTo == null) {
      return switch (kind) {
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
          'images': [
            for (final image in images ?? const <ChatImageItem>[])
              image.toJson(),
          ],
        }),
      };
    }

    final envelope = <String, dynamic>{
      'type': _kindName,
      'reply_to': replyTo!.toJson(),
    };
    switch (kind) {
      case ChatMessageKind.text:
        envelope['text'] = text ?? '';
      case ChatMessageKind.image:
        envelope['url'] = url;
        envelope['name'] = name ?? '';
      case ChatMessageKind.audio:
        envelope['url'] = url;
        envelope['duration'] = duration ?? 0;
      case ChatMessageKind.gallery:
        envelope['images'] = [
          for (final image in images ?? const <ChatImageItem>[])
            image.toJson(),
        ];
    }
    return jsonEncode(envelope);
  }

  String get _kindName => switch (kind) {
    ChatMessageKind.text => 'text',
    ChatMessageKind.image => 'image',
    ChatMessageKind.audio => 'audio',
    ChatMessageKind.gallery => 'gallery',
  };

  static ChatMessageContent decode(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('{')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) {
          final replyTo = _parseReply(decoded['reply_to']);
          final type = decoded['type'];
          final url = decoded['url'];
          if (type == 'text') {
            return ChatMessageContent._(
              kind: ChatMessageKind.text,
              text: (decoded['text'] as String?) ?? '',
              replyTo: replyTo,
            );
          }
          if (type == 'image' && url is String && url.isNotEmpty) {
            return ChatMessageContent._(
              kind: ChatMessageKind.image,
              url: url,
              name: (decoded['name'] as String?) ?? '',
              replyTo: replyTo,
            );
          }
          if (type == 'audio' && url is String && url.isNotEmpty) {
            final duration = decoded['duration'];
            return ChatMessageContent._(
              kind: ChatMessageKind.audio,
              url: url,
              duration: duration is num ? duration.toDouble() : 0,
              replyTo: replyTo,
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
                return ChatMessageContent._(
                  kind: ChatMessageKind.gallery,
                  images: images,
                  replyTo: replyTo,
                );
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

  static ChatReplyQuote? _parseReply(Object? value) {
    if (value is Map) {
      return ChatReplyQuote.fromJson(Map<String, dynamic>.from(value));
    }
    return null;
  }
}
