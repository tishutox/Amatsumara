import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lumii_quest/features/chats/crypto/chat_crypto_service.dart';
import 'package:lumii_quest/features/chats/data/chat_repository.dart';
import 'package:lumii_quest/features/chats/domain/chat_message_content.dart';
import 'package:lumii_quest/features/chats/presentation/recording_file_io.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatDetailPage extends StatefulWidget {
  const ChatDetailPage({
    required this.conversationId,
    required this.friendId,
    required this.displayName,
    super.key,
  });

  final String conversationId;
  final String friendId;
  final String displayName;

  @override
  State<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends State<ChatDetailPage> {
  final _repository = ChatRepository();
  final _crypto = const ChatCryptoService();
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _recorder = AudioRecorder();
  bool _isSending = false;
  bool _isRecording = false;
  StreamSubscription<Amplitude>? _amplitudeSub;
  DateTime? _recordingStartedAt;
  final List<double> _amplitudes = [];
  ChatDeviceIdentity? _localIdentity;
  List<ChatDeviceRecipient> _recipientDevices = const [];
  int _friendDeviceCount = 0;
  String? _legacyFriendPublicKey;
  String? _setupError;

  bool get _supportsMedia =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.windows);

  @override
  void initState() {
    super.initState();
    _prepareEncryption();
    _messageController.addListener(_handleTextChanged);
  }

  void _handleTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _messageController.removeListener(_handleTextChanged);
    _messageController.dispose();
    _scrollController.dispose();
    _amplitudeSub?.cancel();
    unawaited(_recorder.dispose());
    super.dispose();
  }

  Future<void> _prepareEncryption() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        setState(() => _setupError = 'Sign in to use encrypted chats.');
        return;
      }
      final identity = await _crypto.ensureDeviceIdentity();
      await _repository.upsertIdentityKey(identity.publicKey);
      await _repository.upsertDeviceKey(
        deviceId: identity.deviceId,
        publicKey: identity.publicKey,
        deviceName: identity.deviceName,
      );
      final deviceKeys = await _repository.listActiveDeviceKeys([
        user.id,
        widget.friendId,
      ]);
      final legacyFriendPublicKey = await _repository.getPublicKey(
        widget.friendId,
      );
      final friendDeviceCount = deviceKeys
          .where((device) => device.userId == widget.friendId)
          .length;
      if (!mounted) {
        return;
      }
      setState(() {
        _localIdentity = identity;
        _recipientDevices = [
          for (final device in deviceKeys)
            ChatDeviceRecipient(
              deviceId: device.deviceId,
              publicKey: device.publicKey,
            ),
        ];
        _friendDeviceCount = friendDeviceCount;
        _legacyFriendPublicKey = legacyFriendPublicKey;
        _setupError = friendDeviceCount == 0
            ? '${widget.displayName} needs to open Chats once before encrypted messages can be sent.'
            : null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _setupError = 'Encryption could not be prepared: $error');
    }
  }

  Future<void> _refresh() async {
    await _prepareEncryption();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Encryption keys refreshed.')),
      );
    }
  }

  Future<void> _scrollToBottom() async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (_scrollController.hasClients) {
      await _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> _deliverContent(String content) async {
    final identity = _localIdentity;
    if (content.isEmpty ||
        identity == null ||
        _recipientDevices.isEmpty ||
        _friendDeviceCount == 0) {
      return;
    }
    final encrypted = await _crypto.encryptForDevices(
      conversationId: widget.conversationId,
      senderDeviceId: identity.deviceId,
      recipients: _recipientDevices,
      message: content,
    );
    await _repository.sendMessage(
      conversationId: widget.conversationId,
      senderDeviceId: identity.deviceId,
      encryptedPayload: encrypted.value,
    );
  }

  Future<void> _sendText() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending || _isRecording) {
      return;
    }
    setState(() => _isSending = true);
    try {
      await _deliverContent(text);
      _messageController.clear();
      await _scrollToBottom();
    } catch (error) {
      _showError('Message could not be sent: $error');
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _sendImages() async {
    if (_isSending || _isRecording) {
      return;
    }
    final images = await ImagePicker().pickMultiImage(
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (images.isEmpty || !mounted) {
      return;
    }
    setState(() => _isSending = true);
    try {
      for (final image in images) {
        await _sendImage(image);
      }
      await _scrollToBottom();
    } catch (error) {
      _showError('Image could not be sent: $error');
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _sendImage(XFile image) async {
    final bytes = await image.readAsBytes();
    final extension = _imageExtension(image.name);
    final url = await _repository.uploadChatMedia(
      bytes: bytes,
      extension: extension,
      contentType: _imageContentType(extension),
    );
    await _deliverContent(
      ChatMessageContent.image(url: url, name: image.name).encode(),
    );
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _cancelRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    if (_isSending) {
      return;
    }
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      _showError('Microphone permission is required to record.');
      return;
    }
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final encoder = isAndroid ? AudioEncoder.aacLc : AudioEncoder.wav;
    final extension = isAndroid ? 'm4a' : 'wav';
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/lumii_voice_${DateTime.now().millisecondsSinceEpoch}.$extension';
    try {
      await _recorder.start(RecordConfig(encoder: encoder), path: path);
    } catch (error) {
      _showError('Recording could not start: $error');
      return;
    }
    _amplitudes.clear();
    _amplitudeSub?.cancel();
    _amplitudeSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 120))
        .listen((amplitude) {
          if (mounted) {
            setState(() => _amplitudes.add(amplitude.current));
          }
        });
    if (mounted) {
      setState(() {
        _isRecording = true;
        _recordingStartedAt = DateTime.now();
      });
    }
  }

  Future<void> _cancelRecording() async {
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    await _recorder.cancel();
    if (mounted) {
      setState(() {
        _isRecording = false;
        _amplitudes.clear();
        _recordingStartedAt = null;
      });
    }
  }

  Future<void> _finishRecording() async {
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    final path = await _recorder.stop();
    if (!mounted) {
      return;
    }
    final duration = _recordingStartedAt == null
        ? 0.0
        : DateTime.now().difference(_recordingStartedAt!).inMilliseconds /
              1000.0;
    setState(() {
      _isRecording = false;
      _amplitudes.clear();
      _recordingStartedAt = null;
    });
    if (path == null) {
      return;
    }
    setState(() => _isSending = true);
    try {
      final bytes = await readRecordingFile(path);
      final extension = _audioExtension(path);
      final url = await _repository.uploadChatMedia(
        bytes: bytes,
        extension: extension,
        contentType: _audioContentType(extension),
      );
      await _deliverContent(
        ChatMessageContent.audio(url: url, duration: duration).encode(),
      );
      await _scrollToBottom();
    } catch (error) {
      _showError('Voice message could not be sent: $error');
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        final themedPrimary = Theme.of(context).colorScheme.primary;
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Back',
              onPressed: () => context.pop(),
              icon: const Icon(LucideIcons.chevronLeft),
            ),
            title: Text(widget.displayName),
            foregroundColor: themedPrimary,
            surfaceTintColor: Colors.transparent,
            actions: [
              IconButton(
                tooltip: 'Refresh',
                onPressed: _refresh,
                icon: const Icon(LucideIcons.refreshCcw),
              ),
            ],
          ),
          body: _ChatDetailBody(
            setupError: _setupError,
            repository: _repository,
            conversationId: widget.conversationId,
            crypto: _crypto,
            legacyFriendPublicKey: _legacyFriendPublicKey,
            scrollController: _scrollController,
            messageController: _messageController,
            friendDeviceCount: _friendDeviceCount,
            isSending: _isSending,
            isRecording: _isRecording,
            supportsMedia: _supportsMedia,
            amplitudes: _amplitudes,
            onRefresh: _refresh,
            onSend: _sendText,
            onPickImages: _sendImages,
            onToggleRecording: _toggleRecording,
            onCancelRecording: _cancelRecording,
            onFinishRecording: _finishRecording,
          ),
        );
      },
    );
  }
}

class _ChatDetailBody extends StatelessWidget {
  const _ChatDetailBody({
    required this.setupError,
    required this.repository,
    required this.conversationId,
    required this.crypto,
    required this.legacyFriendPublicKey,
    required this.scrollController,
    required this.messageController,
    required this.friendDeviceCount,
    required this.isSending,
    required this.isRecording,
    required this.supportsMedia,
    required this.amplitudes,
    required this.onRefresh,
    required this.onSend,
    required this.onPickImages,
    required this.onToggleRecording,
    required this.onCancelRecording,
    required this.onFinishRecording,
  });

  final String? setupError;
  final ChatRepository repository;
  final String conversationId;
  final ChatCryptoService crypto;
  final String? legacyFriendPublicKey;
  final ScrollController scrollController;
  final TextEditingController messageController;
  final int friendDeviceCount;
  final bool isSending;
  final bool isRecording;
  final bool supportsMedia;
  final List<double> amplitudes;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onSend;
  final Future<void> Function() onPickImages;
  final Future<void> Function() onToggleRecording;
  final Future<void> Function() onCancelRecording;
  final Future<void> Function() onFinishRecording;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (setupError != null)
          MaterialBanner(
            content: Text(setupError!),
            leading: const Icon(LucideIcons.lock),
            actions: [
              TextButton(onPressed: onRefresh, child: const Text('Refresh')),
            ],
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            child: StreamBuilder<List<ChatMessage>>(
              stream: repository.watchMessages(conversationId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const _ChatInfoState(
                    icon: LucideIcons.triangleAlert,
                    message: 'Messages could not be loaded.',
                  );
                }
                final messages = snapshot.data ?? const [];
                if (messages.isEmpty) {
                  return const _ChatInfoState(
                    icon: LucideIcons.messageCircle,
                    message: 'No messages yet. Say hi.',
                  );
                }
                return ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    return _MessageBubble(
                      message: messages[index],
                      conversationId: conversationId,
                      crypto: crypto,
                      legacyFriendPublicKey: legacyFriendPublicKey,
                    );
                  },
                );
              },
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: _buildInput(context),
        ),
      ],
    );
  }

  Widget _buildInput(BuildContext context) {
    if (supportsMedia) {
      if (isRecording) {
        return _RecordingInputBar(
          amplitudes: amplitudes,
          onCancel: onCancelRecording,
          onFinish: onFinishRecording,
        );
      }
      return _MediaInputBar(
        controller: messageController,
        friendDeviceCount: friendDeviceCount,
        isSending: isSending,
        onSend: onSend,
        onPickImages: onPickImages,
        onToggleRecording: onToggleRecording,
      );
    }
    return _LegacyInputBar(
      controller: messageController,
      friendDeviceCount: friendDeviceCount,
      isSending: isSending,
      onSend: onSend,
    );
  }
}

class _MediaInputBar extends StatelessWidget {
  const _MediaInputBar({
    required this.controller,
    required this.friendDeviceCount,
    required this.isSending,
    required this.onSend,
    required this.onPickImages,
    required this.onToggleRecording,
  });

  final TextEditingController controller;
  final int friendDeviceCount;
  final bool isSending;
  final Future<void> Function() onSend;
  final Future<void> Function() onPickImages;
  final Future<void> Function() onToggleRecording;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final hasText = controller.text.trim().isNotEmpty;
    final canSend = friendDeviceCount > 0 && !isSending;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              enabled: friendDeviceCount > 0 && !isSending,
              decoration: InputDecoration(
                hintText: friendDeviceCount == 0
                    ? 'Waiting for encryption key...'
                    : 'Message',
                filled: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(50),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (hasText)
            _CircleIconButton(
              tooltip: 'Send',
              icon: isSending
                  ? LucideIcons.loaderCircle
                  : LucideIcons.sendHorizontal,
              backgroundColor: primary,
              iconColor: Colors.white,
              onPressed: canSend ? onSend : null,
            )
          else ...[
            IconButton(
              tooltip: 'Voice message',
              onPressed: friendDeviceCount == 0 || isSending
                  ? null
                  : onToggleRecording,
              icon: Icon(LucideIcons.mic, color: primary),
            ),
            const SizedBox(width: 4),
            _CircleIconButton(
              tooltip: 'Send images',
              icon: LucideIcons.circlePlus,
              backgroundColor: primary,
              iconColor: Colors.white,
              onPressed: canSend ? onPickImages : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _RecordingInputBar extends StatelessWidget {
  const _RecordingInputBar({
    required this.amplitudes,
    required this.onCancel,
    required this.onFinish,
  });

  final List<double> amplitudes;
  final VoidCallback onCancel;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final error = Theme.of(context).colorScheme.error;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
          _CircleIconButton(
            tooltip: 'Cancel recording',
            icon: LucideIcons.trash,
            backgroundColor: error.withValues(alpha: 0.14),
            iconColor: error,
            onPressed: onCancel,
          ),
          const SizedBox(width: 12),
          Expanded(child: _RecordingWaveform(amplitudes: amplitudes)),
          const SizedBox(width: 12),
          _CircleIconButton(
            tooltip: 'Send voice message',
            icon: LucideIcons.sendHorizontal,
            backgroundColor: primary,
            iconColor: Colors.white,
            onPressed: onFinish,
          ),
        ],
      ),
    );
  }
}

class _LegacyInputBar extends StatelessWidget {
  const _LegacyInputBar({
    required this.controller,
    required this.friendDeviceCount,
    required this.isSending,
    required this.onSend,
  });

  final TextEditingController controller;
  final int friendDeviceCount;
  final bool isSending;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              enabled: friendDeviceCount > 0 && !isSending,
              decoration: InputDecoration(
                hintText: friendDeviceCount == 0
                    ? 'Waiting for encryption key...'
                    : 'Message',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: friendDeviceCount == 0 || isSending ? null : onSend,
            child: Icon(
              isSending ? LucideIcons.loaderCircle : LucideIcons.sendHorizontal,
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.tooltip,
    required this.icon,
    required this.backgroundColor,
    required this.iconColor,
    this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color backgroundColor;
  final Color iconColor;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, color: iconColor),
      ),
    );
  }
}

class _RecordingWaveform extends StatelessWidget {
  const _RecordingWaveform({required this.amplitudes});

  final List<double> amplitudes;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final samples = amplitudes.isEmpty
        ? List<double>.filled(28, 0.25)
        : amplitudes.length > 40
        ? amplitudes.sublist(amplitudes.length - 40)
        : amplitudes;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(50),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final value in samples)
            Container(
              width: 3,
              height: 6 + _normalizeAmplitude(value) * 36,
              decoration: BoxDecoration(
                color: primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}

double _normalizeAmplitude(double db) {
  return ((db + 60) / 60).clamp(0.06, 1.0);
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.conversationId,
    required this.crypto,
    required this.legacyFriendPublicKey,
  });

  final ChatMessage message;
  final String conversationId;
  final ChatCryptoService crypto;
  final String? legacyFriendPublicKey;

  @override
  Widget build(BuildContext context) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isMine = message.senderId == currentUserId;
    final primary = Theme.of(context).colorScheme.primary;
    final bubbleColor = isMine
        ? primary
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    final textColor = isMine
        ? Theme.of(context).colorScheme.onPrimary
        : Theme.of(context).colorScheme.onSurface;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          color: bubbleColor,
          clipBehavior: Clip.antiAlias,
          child: FutureBuilder<String>(
            future: crypto.decrypt(
              conversationId: conversationId,
              encryptedPayload: message.encryptedPayload,
              remotePublicKey: isMine ? legacyFriendPublicKey : null,
            ),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Text(
                    'This encrypted message was not prepared for this device. Refresh keys, then new messages will work here.',
                    style: TextStyle(color: textColor),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Text('Decrypting...', style: TextStyle(color: textColor)),
                );
              }
              final content = ChatMessageContent.decode(snapshot.data!);
              switch (content.kind) {
                case ChatMessageKind.text:
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Text(
                      content.text ?? '',
                      style: TextStyle(color: textColor),
                    ),
                  );
                case ChatMessageKind.image:
                  return _ImageMessageBubble(url: content.url!);
                case ChatMessageKind.audio:
                  return _AudioMessageBubble(
                    url: content.url!,
                    duration: content.duration ?? 0,
                    textColor: textColor,
                  );
              }
            },
          ),
        ),
      ),
    );
  }
}

class _ImageMessageBubble extends StatelessWidget {
  const _ImageMessageBubble({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Image.network(
        url,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        loadingBuilder: (context, child, progress) {
          if (progress == null) {
            return child;
          }
          return const SizedBox(
            width: 220,
            height: 160,
            child: Center(child: CircularProgressIndicator()),
          );
        },
        errorBuilder: (_, _, _) => const SizedBox(
          width: 220,
          height: 120,
          child: Center(child: Icon(LucideIcons.imageOff)),
        ),
      ),
    );
  }
}

class _AudioMessageBubble extends StatefulWidget {
  const _AudioMessageBubble({
    required this.url,
    required this.duration,
    required this.textColor,
  });

  final String url;
  final double duration;
  final Color textColor;

  @override
  State<_AudioMessageBubble> createState() => _AudioMessageBubbleState();
}

class _AudioMessageBubbleState extends State<_AudioMessageBubble> {
  final _player = AudioPlayer();
  bool _isPlaying = false;
  StreamSubscription<void>? _completeSub;

  @override
  void initState() {
    super.initState();
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() => _isPlaying = false);
      }
    });
  }

  @override
  void dispose() {
    _completeSub?.cancel();
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_isPlaying) {
      await _player.stop();
      if (mounted) {
        setState(() => _isPlaying = false);
      }
      return;
    }
    await _player.play(UrlSource(widget.url));
    if (mounted) {
      setState(() => _isPlaying = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: _isPlaying ? 'Pause' : 'Play',
            onPressed: _toggle,
            icon: Icon(
              _isPlaying ? LucideIcons.pause : LucideIcons.play,
              color: widget.textColor,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            _formatDuration(widget.duration),
            style: TextStyle(color: widget.textColor),
          ),
        ],
      ),
    );
  }
}

String _formatDuration(double seconds) {
  final total = seconds.round();
  final minutes = total ~/ 60;
  final secs = total % 60;
  return minutes > 0
      ? '$minutes:${secs.toString().padLeft(2, '0')}'
      : '0:${secs.toString().padLeft(2, '0')}';
}

String _imageExtension(String fileName) {
  final extension = fileName.split('.').last.toLowerCase();
  return switch (extension) {
    'jpg' || 'jpeg' => 'jpg',
    'png' => 'png',
    'webp' => 'webp',
    'gif' => 'gif',
    _ => 'jpg',
  };
}

String _imageContentType(String extension) => switch (extension) {
  'png' => 'image/png',
  'webp' => 'image/webp',
  'gif' => 'image/gif',
  _ => 'image/jpeg',
};

String _audioExtension(String path) {
  final extension = path.split('.').last.toLowerCase();
  return extension.isEmpty ? 'm4a' : extension;
}

String _audioContentType(String extension) => switch (extension) {
  'wav' => 'audio/wav',
  'ogg' => 'audio/ogg',
  _ => 'audio/mp4',
};

class _ChatInfoState extends StatelessWidget {
  const _ChatInfoState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: primary, size: 44),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
