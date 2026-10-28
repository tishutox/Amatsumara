import 'dart:async';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lumii_quest/features/chats/crypto/chat_crypto_service.dart';
import 'package:lumii_quest/features/chats/data/chat_repository.dart';
import 'package:lumii_quest/features/chats/domain/chat_message_content.dart';
import 'package:lumii_quest/features/chats/presentation/chat_gallery_page.dart';
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
  bool _showAttachMenu = false;
  final _inputAreaKey = GlobalKey();
  double _inputAreaHeight = 0;
  bool _didInitialScroll = false;
  ChatReplyQuote? _replyTarget;
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToLatestOnce());
  }

  void _scrollToLatestOnce() {
    if (_didInitialScroll) return;
    _didInitialScroll = true;
    _attemptInitialScroll(6);
  }

  Future<void> _attemptInitialScroll(int remaining) async {
    if (remaining <= 0 || !mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    if (_scrollController.hasClients &&
        _scrollController.position.maxScrollExtent > 0) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      return;
    }
    await _attemptInitialScroll(remaining - 1);
  }

  void _setAttachMenu(bool show) {
    if (_showAttachMenu == show) return;
    setState(() => _showAttachMenu = show);
  }

  void _measureInputArea() {
    final box = _inputAreaKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    if (box.size.height != _inputAreaHeight) {
      setState(() => _inputAreaHeight = box.size.height);
    }
  }

  void _handleTextChanged() {
    if (!mounted) return;
    if (_messageController.text.trim().isNotEmpty && _showAttachMenu) {
      _setAttachMenu(false);
    } else {
      setState(() {});
    }
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

  void _showInfo(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> _deliverContent(ChatMessageContent content) async {
    final identity = _localIdentity;
    if (identity == null ||
        _recipientDevices.isEmpty ||
        _friendDeviceCount == 0) {
      return;
    }
    final replyTo = _replyTarget;
    final message = content.withReply(replyTo).encode();
    final encrypted = await _crypto.encryptForDevices(
      conversationId: widget.conversationId,
      senderDeviceId: identity.deviceId,
      recipients: _recipientDevices,
      message: message,
    );
    await _repository.sendMessage(
      conversationId: widget.conversationId,
      senderDeviceId: identity.deviceId,
      encryptedPayload: encrypted.value,
    );
    if (replyTo != null && mounted) {
      setState(() => _replyTarget = null);
    }
  }

  Future<void> _sendText() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending || _isRecording) {
      return;
    }
    setState(() => _isSending = true);
    try {
      await _deliverContent(ChatMessageContent.text(text));
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
      final items = <ChatImageItem>[];
      for (final image in images) {
        final bytes = await image.readAsBytes();
        final aspectRatio = await _readAspectRatio(bytes);
        final extension = _imageExtension(image.name);
        final url = await _repository.uploadChatMedia(
          bytes: bytes,
          extension: extension,
          contentType: _imageContentType(extension),
        );
        items.add(ChatImageItem(url: url, aspectRatio: aspectRatio));
      }
      await _deliverContent(ChatMessageContent.gallery(items));
      await _scrollToBottom();
    } catch (error) {
      _showError('Image could not be sent: $error');
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<double> _readAspectRatio(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final ratio = image.height == 0 ? 0.0 : image.width / image.height;
      image.dispose();
      codec.dispose();
      return ratio;
    } catch (_) {
      return 0;
    }
  }

  void _toggleAttachMenu() => _setAttachMenu(!_showAttachMenu);

  Future<void> _pickSticker() async {
    _setAttachMenu(false);
    _showError('Stickers are coming soon.');
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
        _showAttachMenu = false;
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
        ChatMessageContent.audio(url: url, duration: duration),
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

  void _cancelReply() {
    setState(() => _replyTarget = null);
  }

  void _startCall() {
    context.push(
      Uri(
        path: '/call/${widget.friendId}',
        queryParameters: {'name': widget.displayName},
      ).toString(),
    );
  }

  Future<void> _forwardRaw(
    String rawContent,
    String conversationId,
    String friendId,
  ) async {
    final user = Supabase.instance.client.auth.currentUser;
    final identity = _localIdentity;
    if (user == null || identity == null) {
      return;
    }
    final deviceKeys = await _repository.listActiveDeviceKeys([
      user.id,
      friendId,
    ]);
    final recipients = [
      for (final device in deviceKeys)
        ChatDeviceRecipient(
          deviceId: device.deviceId,
          publicKey: device.publicKey,
        ),
    ];
    if (recipients.isEmpty) {
      throw StateError('The recipient has no device keys yet.');
    }
    final encrypted = await _crypto.encryptForDevices(
      conversationId: conversationId,
      senderDeviceId: identity.deviceId,
      recipients: recipients,
      message: rawContent,
    );
    await _repository.sendMessage(
      conversationId: conversationId,
      senderDeviceId: identity.deviceId,
      encryptedPayload: encrypted.value,
    );
  }

  Future<void> _forwardMessage(String decryptedContent) async {
    final chats = await _repository.listChats();
    final targets = chats
        .where((chat) => chat.conversationId != widget.conversationId)
        .toList();
    if (!mounted) return;
    if (targets.isEmpty) {
      _showError('No other chats available to forward to.');
      return;
    }
    final target = await showModalBottomSheet<ChatPreview>(
      context: context,
      builder: (_) => _ForwardPicker(chats: targets),
    );
    if (target == null || !mounted) return;
    setState(() => _isSending = true);
    try {
      await _forwardRaw(
        decryptedContent,
        target.conversationId,
        target.friendId,
      );
      _showInfo('Message forwarded to ${target.displayName}.');
    } catch (error) {
      _showError('Message could not be forwarded: $error');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _deleteMessageForAll(ChatMessage message) async {
    setState(() => _isSending = true);
    try {
      await _repository.deleteMessageForAll(message.id);
    } catch (error) {
      _showError('Message could not be deleted: $error');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _deleteMessageForMe(ChatMessage message) async {
    setState(() => _isSending = true);
    try {
      await _repository.deleteMessageForMe(message.id);
    } catch (error) {
      _showError('Message could not be deleted: $error');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<String?> _showMenuAt(
    BuildContext context,
    Offset globalPosition,
    List<PopupMenuEntry<String>> items,
  ) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    return showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: items,
    );
  }

  Future<void> _showMessageContextMenu(
    BuildContext context,
    Offset globalPosition,
    ChatMessage message,
    String decryptedContent,
  ) async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isMine = message.senderId == currentUserId;
    final senderName = isMine ? 'You' : widget.displayName;
    final preview = ChatMessageContent.decode(decryptedContent).preview;

    final action = await _showMenuAt(context, globalPosition, [
      const PopupMenuItem(
        value: 'reply',
        child: _MenuRow(icon: LucideIcons.reply, label: 'Reply'),
      ),
      const PopupMenuItem(
        value: 'redirect',
        child: _MenuRow(icon: LucideIcons.send, label: 'Redirect'),
      ),
      const PopupMenuItem(
        value: 'delete',
        child: _MenuRow(icon: LucideIcons.trash, label: 'Delete'),
      ),
    ]);

    if (!mounted || action == null) return;

    switch (action) {
      case 'reply':
        setState(() {
          _replyTarget = ChatReplyQuote(
            messageId: message.id,
            senderName: senderName,
            preview: preview,
          );
        });
      case 'redirect':
        await _forwardMessage(decryptedContent);
      case 'delete':
        if (!context.mounted) return;
        final deleteAction = await _showMenuAt(context, globalPosition, [
          const PopupMenuItem(
            value: 'delete_all',
            child: _MenuRow(icon: LucideIcons.trash, label: 'Delete for All'),
          ),
          const PopupMenuItem(
            value: 'delete_me',
            child: _MenuRow(icon: LucideIcons.userX, label: 'Delete for Me'),
          ),
        ]);
        if (!mounted || deleteAction == null) return;
        if (deleteAction == 'delete_all') {
          await _deleteMessageForAll(message);
        } else if (deleteAction == 'delete_me') {
          await _deleteMessageForMe(message);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureInputArea());
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
                tooltip: 'Video call',
                onPressed: () {},
                icon: const Icon(LucideIcons.video),
              ),
              IconButton(
                tooltip: 'Voice call',
                onPressed: _startCall,
                icon: const Icon(LucideIcons.phone),
              ),
            ],
          ),
          body: Stack(
            clipBehavior: Clip.none,
            children: [
              _ChatDetailBody(
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
                showAttachMenu: _showAttachMenu,
                onToggleAttachMenu: _toggleAttachMenu,
                onPickSticker: _pickSticker,
                replyTarget: _replyTarget,
                onCancelReply: _cancelReply,
                onMessageMenu: _showMessageContextMenu,
                inputAreaKey: _inputAreaKey,
              ),
              if (_showAttachMenu)
                Positioned(
                  right: 16,
                  bottom: _inputAreaHeight + 8,
                  child: _AttachMenu(
                    onGallery: _sendImages,
                    onSticker: _pickSticker,
                  ),
                ),
            ],
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
    required this.showAttachMenu,
    required this.onToggleAttachMenu,
    required this.onPickSticker,
    required this.replyTarget,
    required this.onCancelReply,
    required this.onMessageMenu,
    required this.inputAreaKey,
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
  final bool showAttachMenu;
  final VoidCallback onToggleAttachMenu;
  final Future<void> Function() onPickSticker;
  final ChatReplyQuote? replyTarget;
  final VoidCallback onCancelReply;
  final void Function(
    BuildContext context,
    Offset globalPosition,
    ChatMessage message,
    String decryptedContent,
  )
  onMessageMenu;
  final GlobalKey inputAreaKey;

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
                      onMessageMenu: onMessageMenu,
                    );
                  },
                );
              },
            ),
          ),
        ),
        KeyedSubtree(
          key: inputAreaKey,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (replyTarget != null)
                  _ReplyComposerBar(
                    quote: replyTarget!,
                    onCancel: onCancelReply,
                  ),
                _buildInput(context),
              ],
            ),
          ),
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
        showAttachMenu: showAttachMenu,
        onSend: onSend,
        onToggleAttachMenu: onToggleAttachMenu,
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
    required this.showAttachMenu,
    required this.onSend,
    required this.onToggleAttachMenu,
    required this.onToggleRecording,
  });

  final TextEditingController controller;
  final int friendDeviceCount;
  final bool isSending;
  final bool showAttachMenu;
  final Future<void> Function() onSend;
  final VoidCallback onToggleAttachMenu;
  final Future<void> Function() onToggleRecording;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final surface = Theme.of(context).colorScheme.surfaceContainerHighest;
    final hasText = controller.text.trim().isNotEmpty;
    final canSend = friendDeviceCount > 0 && !isSending;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(50),
        ),
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
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
              ),
            ),
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
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 44,
                  minHeight: 44,
                ),
                icon: Icon(LucideIcons.mic, color: primary),
              ),
              AnimatedRotation(
                turns: showAttachMenu ? 0.125 : 0,
                duration: const Duration(milliseconds: 200),
                child: _CircleIconButton(
                  tooltip: 'Attach',
                  icon: LucideIcons.circlePlus,
                  backgroundColor: primary,
                  iconColor: Colors.white,
                  onPressed: canSend ? onToggleAttachMenu : null,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AttachMenu extends StatelessWidget {
  const _AttachMenu({required this.onGallery, required this.onSticker});

  final VoidCallback onGallery;
  final VoidCallback onSticker;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final surface = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Material(
      color: surface,
      elevation: 4,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AttachOption(
              icon: LucideIcons.image,
              label: 'Gallery',
              color: primary,
              onTap: onGallery,
            ),
            const SizedBox(width: 4),
            _AttachOption(
              icon: LucideIcons.sticker,
              label: 'Sticker',
              color: primary,
              onTap: onSticker,
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachOption extends StatelessWidget {
  const _AttachOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Icon(icon, color: color),
        ),
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
    final surface = Theme.of(context).colorScheme.surfaceContainerHighest;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(50),
        ),
        child: Row(
          children: [
            _CircleIconButton(
              tooltip: 'Cancel recording',
              icon: LucideIcons.trash,
              backgroundColor: error.withValues(alpha: 0.16),
              iconColor: error,
              onPressed: onCancel,
            ),
            const SizedBox(width: 8),
            Expanded(child: _RecordingWaveform(amplitudes: amplitudes)),
            const SizedBox(width: 8),
            _CircleIconButton(
              tooltip: 'Send voice message',
              icon: LucideIcons.sendHorizontal,
              backgroundColor: primary,
              iconColor: Colors.white,
              onPressed: onFinish,
            ),
          ],
        ),
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
      child: SizedBox(
        width: 48,
        height: 48,
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: Icon(icon, color: iconColor, size: 24),
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      child: ClipRect(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < samples.length; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              Container(
                width: 3,
                height: 6 + _normalizeAmplitude(samples[i]) * 36,
                decoration: BoxDecoration(
                  color: primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ],
        ),
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
    required this.onMessageMenu,
  });

  final ChatMessage message;
  final String conversationId;
  final ChatCryptoService crypto;
  final String? legacyFriendPublicKey;
  final void Function(
    BuildContext context,
    Offset globalPosition,
    ChatMessage message,
    String decryptedContent,
  )
  onMessageMenu;

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
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: FutureBuilder<String>(
          future: crypto.decrypt(
            conversationId: conversationId,
            encryptedPayload: message.encryptedPayload,
            remotePublicKey: isMine ? legacyFriendPublicKey : null,
          ),
          builder: (context, snapshot) {
            final Widget bubble;
            if (snapshot.hasError) {
              bubble = _bubble(
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Text(
                    'This encrypted message was not prepared for this device. Refresh keys, then new messages will work here.',
                    style: TextStyle(color: textColor),
                  ),
                ),
                bubbleColor,
              );
            } else if (!snapshot.hasData) {
              bubble = _bubble(
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Text('Decrypting...', style: TextStyle(color: textColor)),
                ),
                bubbleColor,
              );
            } else {
              final content = ChatMessageContent.decode(snapshot.data!);
              bubble = _buildContent(
                context,
                content,
                textColor,
                bubbleColor,
                onSurface,
              );
            }

            if (!snapshot.hasData) {
              return bubble;
            }
            return GestureDetector(
              onLongPressStart: (details) => onMessageMenu(
                context,
                details.globalPosition,
                message,
                snapshot.data!,
              ),
              onSecondaryTapUp: (details) => onMessageMenu(
                context,
                details.globalPosition,
                message,
                snapshot.data!,
              ),
              child: bubble,
            );
          },
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    ChatMessageContent content,
    Color textColor,
    Color bubbleColor,
    Color onSurface,
  ) {
    switch (content.kind) {
      case ChatMessageKind.text:
        return _bubble(
          _withReply(
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              child: Text(
                content.text ?? '',
                style: TextStyle(color: textColor),
              ),
            ),
            content.replyTo,
            textColor,
          ),
          bubbleColor,
        );
      case ChatMessageKind.image:
        return _withReply(
          _ImageMessageBubble(url: content.url!),
          content.replyTo,
          onSurface,
        );
      case ChatMessageKind.audio:
        return _bubble(
          _withReply(
            _AudioMessageBubble(
              url: content.url!,
              duration: content.duration ?? 0,
              textColor: textColor,
            ),
            content.replyTo,
            textColor,
          ),
          bubbleColor,
        );
      case ChatMessageKind.gallery:
        return _withReply(
          _GalleryBubble(
            images: content.images ?? const [],
            onTap: () => _openGallery(context, content.images ?? const []),
          ),
          content.replyTo,
          onSurface,
        );
    }
  }

  Widget _withReply(Widget child, ChatReplyQuote? replyTo, Color color) {
    if (replyTo == null) {
      return child;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReplyQuoteBar(quote: replyTo, color: color),
        child,
      ],
    );
  }

  Widget _bubble(Widget child, Color color) {
    return Card(
      color: color,
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  void _openGallery(BuildContext context, List<ChatImageItem> images) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ChatGalleryPage(images: images)),
    );
  }
}

class _GalleryBubble extends StatelessWidget {
  const _GalleryBubble({required this.images, required this.onTap});

  final List<ChatImageItem> images;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visible = images.take(4).toList();
    final anyLandscape = visible.any((image) => image.isLandscape);
    final tile = anyLandscape ? const Size(120, 96) : const Size(96, 120);

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: visible.length == 1
            ? _galleryTile(visible.first, tile)
            : _stack(visible, tile),
      ),
    );
  }

  Widget _stack(List<ChatImageItem> images, Size tile) {
    final n = images.length;
    return SizedBox(
      width: tile.width + 18,
      height: tile.height + (n - 1) * 8 + 14,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = n - 1; i >= 0; i--)
            Positioned(
              left: 9 + _stackDx(i),
              top: _stackDy(i),
              child: Transform.rotate(
                angle: _stackAngle(i),
                child: _galleryTile(images[i], tile),
              ),
            ),
        ],
      ),
    );
  }

  Widget _galleryTile(ChatImageItem image, Size tile) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: tile.width,
        height: tile.height,
        child: Image.network(
          image.url,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : const Center(child: CircularProgressIndicator()),
          errorBuilder: (_, _, _) => const Center(
            child: Icon(LucideIcons.imageOff),
          ),
        ),
      ),
    );
  }
}

double _stackDx(int index) {
  if (index == 0) return 0;
  final direction = index.isOdd ? -1.0 : 1.0;
  return direction * 6.0;
}

double _stackDy(int index) => index * 8.0;

double _stackAngle(int index) {
  if (index == 0) return 0;
  final direction = index.isOdd ? -1.0 : 1.0;
  return direction * 0.12; // ~7 degrees
}

class _ImageMessageBubble extends StatelessWidget {
  const _ImageMessageBubble({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Image.network(
          url,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          loadingBuilder: (context, child, progress) {
            if (progress == null) {
              return child;
            }
            return const SizedBox(
              width: 260,
              height: 190,
              child: Center(child: CircularProgressIndicator()),
            );
          },
          errorBuilder: (_, _, _) => const SizedBox(
            width: 260,
            height: 160,
            child: Center(child: Icon(LucideIcons.imageOff)),
          ),
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

class _ReplyQuoteBar extends StatelessWidget {
  const _ReplyQuoteBar({required this.quote, required this.color});

  final ChatReplyQuote quote;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: color, width: 3),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            quote.senderName,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            quote.preview,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ReplyComposerBar extends StatelessWidget {
  const _ReplyComposerBar({required this.quote, required this.onCancel});

  final ChatReplyQuote quote;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final surface = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      quote.senderName,
                      style: TextStyle(
                        color: primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      quote.preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Cancel reply',
                onPressed: onCancel,
                icon: const Icon(LucideIcons.x),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }
}

class _ForwardPicker extends StatelessWidget {
  const _ForwardPicker({required this.chats});

  final List<ChatPreview> chats;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Forward to',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: chats.length,
              itemBuilder: (context, index) {
                final chat = chats[index];
                final fallbackLetter = chat.displayName.trim().isEmpty
                    ? '?'
                    : chat.displayName.trim().characters.first.toUpperCase();
                return ListTile(
                  leading: CircleAvatar(
                    foregroundImage: chat.avatarUrl == null
                        ? null
                        : NetworkImage(chat.avatarUrl!),
                    child: chat.avatarUrl == null ? Text(fallbackLetter) : null,
                  ),
                  title: Text(chat.displayName),
                  subtitle: Text('@${chat.username}'),
                  onTap: () => Navigator.of(context).pop(chat),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
