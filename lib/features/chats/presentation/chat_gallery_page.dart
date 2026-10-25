import 'package:flutter/material.dart';
import 'package:lumii_quest/features/chats/domain/chat_message_content.dart';
import 'package:lumii_quest/features/chats/presentation/media_download.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Grid gallery opened when tapping an image collection.
class ChatGalleryPage extends StatelessWidget {
  const ChatGalleryPage({required this.images, super.key});

  final List<ChatImageItem> images;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(LucideIcons.x),
        ),
        title: Text(
          '${images.length} ${images.length == 1 ? 'image' : 'images'}',
        ),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(4),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemCount: images.length,
        itemBuilder: (context, index) {
          return GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ChatImageViewerPage(
                  images: images,
                  initialIndex: index,
                ),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                images[index].url,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: Color(0xFF222222),
                  child: Center(
                    child: Icon(LucideIcons.imageOff, color: Colors.white54),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Full-screen swipeable viewer with a download action.
class ChatImageViewerPage extends StatefulWidget {
  const ChatImageViewerPage({
    required this.images,
    required this.initialIndex,
    super.key,
  });

  final List<ChatImageItem> images;
  final int initialIndex;

  @override
  State<ChatImageViewerPage> createState() => _ChatImageViewerPageState();
}

class _ChatImageViewerPageState extends State<ChatImageViewerPage> {
  late int _index = widget.initialIndex;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final current = widget.images[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(LucideIcons.chevronLeft),
        ),
        title: Text('${_index + 1} / ${widget.images.length}'),
        actions: [
          IconButton(
            tooltip: 'Download',
            onPressed: _busy ? null : () => _download(current),
            icon: const Icon(LucideIcons.download),
          ),
        ],
      ),
      body: PageView.builder(
        controller: PageController(initialPage: widget.initialIndex),
        itemCount: widget.images.length,
        onPageChanged: (index) => setState(() => _index = index),
        itemBuilder: (context, index) {
          return InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: Center(
              child: Image.network(
                widget.images[index].url,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                errorBuilder: (_, _, _) => const Center(
                  child: Icon(LucideIcons.imageOff, color: Colors.white70),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _download(ChatImageItem image) async {
    setState(() => _busy = true);
    try {
      final extension = _extensionFromUrl(image.url);
      final filename = 'lumii_${DateTime.now().millisecondsSinceEpoch}.$extension';
      await saveImageToDevice(image.url, filename);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image saved to your device.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}

String _extensionFromUrl(String url) {
  final extension = url.split('?').first.split('.').last.toLowerCase();
  return switch (extension) {
    'jpg' || 'jpeg' => 'jpg',
    'png' => 'png',
    'webp' => 'webp',
    'gif' => 'gif',
    _ => 'jpg',
  };
}
