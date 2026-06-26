import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lumii_quest/features/chats/crypto/chat_crypto_service.dart';
import 'package:lumii_quest/features/chats/data/chat_repository.dart';
import 'package:remixicon/remixicon.dart';
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
  String? _friendPublicKey;
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
      final publicKey = await _crypto.ensurePublicKey();
      await _repository.upsertIdentityKey(publicKey);
      final friendPublicKey = await _repository.getPublicKey(widget.friendId);
      if (!mounted) {
        return;
      }
      setState(() {
        _friendPublicKey = friendPublicKey;
        _setupError = friendPublicKey == null
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

  Future<void> _send() async {
    final text = _messageController.text.trim();
    final recipientKey = _friendPublicKey;
    if (text.isEmpty || recipientKey == null || _isSending) {
      return;
    }

    setState(() => _isSending = true);
    try {
      final encrypted = await _crypto.encryptFor(
        conversationId: widget.conversationId,
        recipientPublicKey: recipientKey,
        message: text,
      );
      await _repository.sendMessage(
        conversationId: widget.conversationId,
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
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => context.pop(),
          icon: const Icon(Remix.arrow_left_s_line),
        ),
        title: Text(widget.displayName),
        foregroundColor: primary,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Refresh encryption',
            onPressed: _prepareEncryption,
            icon: const Icon(Remix.shield_keyhole_line),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_setupError != null)
            MaterialBanner(
              content: Text(_setupError!),
              leading: const Icon(Remix.lock_2_line),
              actions: [
                TextButton(
                  onPressed: _prepareEncryption,
                  child: const Text('Retry'),
                ),
              ],
            ),
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: _repository.watchMessages(widget.conversationId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const _ChatInfoState(
                    icon: Remix.error_warning_line,
                    message: 'Messages could not be loaded.',
                  );
                }
                final messages = snapshot.data ?? const [];
                if (messages.isEmpty) {
                  return const _ChatInfoState(
                    icon: Remix.message_3_line,
                    message: 'No messages yet. Say hi ✨',
                  );
                }
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    return _MessageBubble(
                      message: messages[index],
                      conversationId: widget.conversationId,
                      crypto: _crypto,
                      friendPublicKey: _friendPublicKey,
                    );
                  },
                );
              },
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
                      controller: _messageController,
                      minLines: 1,
                      maxLines: 4,
                      enabled: _friendPublicKey != null && !_isSending,
                      decoration: InputDecoration(
                        hintText: _friendPublicKey == null
                            ? 'Waiting for encryption key...'
                            : 'Message',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _friendPublicKey == null || _isSending
                        ? null
                        : _send,
                    child: Icon(
                      _isSending
                          ? Remix.loader_4_line
                          : Remix.send_plane_2_line,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.conversationId,
    required this.crypto,
    required this.friendPublicKey,
  });

  final ChatMessage message;
  final String conversationId;
  final ChatCryptoService crypto;
  final String? friendPublicKey;

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
                remotePublicKey: isMine ? friendPublicKey : null,
              ),
              builder: (context, snapshot) {
                final text = snapshot.hasData
                    ? snapshot.data!
                    : snapshot.hasError
                    ? 'Encrypted message could not be opened on this device.'
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
