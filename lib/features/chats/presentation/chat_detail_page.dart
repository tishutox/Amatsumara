import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lumii_quest/features/chats/crypto/chat_crypto_service.dart';
import 'package:lumii_quest/features/chats/data/chat_repository.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
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
  bool _isSending = false;
  ChatDeviceIdentity? _localIdentity;
  List<ChatDeviceRecipient> _recipientDevices = const [];
  int _friendDeviceCount = 0;
  String? _legacyFriendPublicKey;
  String? _setupError;

  @override
  void initState() {
    super.initState();
    _prepareEncryption();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
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

  Future<void> _send() async {
    final text = _messageController.text.trim();
    final identity = _localIdentity;
    if (text.isEmpty ||
        identity == null ||
        _recipientDevices.isEmpty ||
        _friendDeviceCount == 0 ||
        _isSending) {
      return;
    }

    setState(() => _isSending = true);
    try {
      final encrypted = await _crypto.encryptForDevices(
        conversationId: widget.conversationId,
        senderDeviceId: identity.deviceId,
        recipients: _recipientDevices,
        message: text,
      );
      await _repository.sendMessage(
        conversationId: widget.conversationId,
        senderDeviceId: identity.deviceId,
        encryptedPayload: encrypted.value,
      );
      _messageController.clear();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (_scrollController.hasClients) {
        await _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Message could not be sent: $error')),
        );
      }
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
            onRefresh: _refresh,
            onSend: _send,
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
    required this.onRefresh,
    required this.onSend,
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
  final Future<void> Function() onRefresh;
  final Future<void> Function() onSend;

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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: messageController,
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
                  onPressed: friendDeviceCount == 0 || isSending
                      ? null
                      : onSend,
                  child: Icon(
                    isSending
                        ? LucideIcons.loaderCircle
                        : LucideIcons.sendHorizontal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: FutureBuilder<String>(
              future: crypto.decrypt(
                conversationId: conversationId,
                encryptedPayload: message.encryptedPayload,
                remotePublicKey: isMine ? legacyFriendPublicKey : null,
              ),
              builder: (context, snapshot) {
                final text = snapshot.hasData
                    ? snapshot.data!
                    : snapshot.hasError
                    ? 'This encrypted message was not prepared for this device. Refresh keys, then new messages will work here.'
                    : 'Decrypting...';
                return Text(text, style: TextStyle(color: textColor));
              },
            ),
          ),
        ),
      ),
    );
  }
}

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
