import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lumii_quest/core/icons/app_icons.dart';
import 'package:lumii_quest/features/fern/data/fern_repository.dart';
import 'package:lumii_quest/features/fern/data/local_llm_service.dart';

const Color fernLilac = Color(0xFF8B5CF6);

/// Local-only chat with Fern, the built-in AI assistant.
///
/// Messages are stored on-device (not in the database) and replies come from
/// the Ollama cloud API.
class FernPage extends StatefulWidget {
  const FernPage({super.key});

  @override
  State<FernPage> createState() => _FernPageState();
}

class _FernPageState extends State<FernPage> {
  final _repository = FernRepository();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  List<FernMessage> _messages = [];
  bool _sending = false;
  bool _downloadingModel = false;
  double? _downloadProgress;
  bool _localModelReady = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(_checkLocalModel());
    unawaited(_checkCrashLog());
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final messages = await _repository.loadMessages();
    if (mounted) {
      setState(() => _messages = messages);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  Future<void> _checkLocalModel() async {
    final ready = LocalLlmService.instance.isModelLoaded;
    if (mounted) setState(() => _localModelReady = ready);
  }

  Future<void> _checkCrashLog() async {
    final log = await LocalLlmService.instance.readCrashLog();
    if (!mounted || log == null || log.trim().isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Native crash log'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(log, style: const TextStyle(fontSize: 12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: log));
              Navigator.of(context).pop();
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadModel() async {
    if (_downloadingModel) return;
    setState(() {
      _downloadingModel = true;
      _downloadProgress = 0;
    });
    try {
      final ok = await LocalLlmService.instance.ensureLoaded(
        onProgress: (p) {
          if (mounted) setState(() => _downloadProgress = p);
        },
      );
      if (mounted) setState(() => _localModelReady = ok);
      if (mounted && !ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load the local model.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Model download failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloadingModel = false);
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    _controller.clear();

    final history = List<FernMessage>.of(_messages);
    setState(() {
      _messages = [
        ..._messages,
        FernMessage(role: 'user', content: text, sentAt: DateTime.now()),
      ];
      _sending = true;
    });
    _scrollToBottom();

    try {
      final reply = await _repository.sendMessage(history, text);
      if (!mounted) return;
      setState(() {
        _messages = [
          ..._messages,
          FernMessage(role: 'assistant', content: reply, sentAt: DateTime.now()),
        ];
      });
      await _repository.saveMessages(_messages);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messages = [
          ..._messages,
          FernMessage(
            role: 'assistant',
            content: 'Sorry, something went wrong: $error',
            sentAt: DateTime.now(),
          ),
        ];
      });
      await _repository.saveMessages(_messages);
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final surface = Theme.of(context).colorScheme.surfaceContainerHighest;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => context.pop(),
          icon: const AppIcon(AppIcons.chevronLeft),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
              radius: 16,
              backgroundImage: AssetImage('fern/fern.png'),
            ),
            const SizedBox(width: 8),
            const Text('Fern'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: fernLilac.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const AppIcon(AppIcons.bot, size: 16, color: fernLilac),
            ),
          ],
        ),
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (LocalLlmService.instance.isSupported && !_localModelReady)
              _buildLocalModelBanner(),
            Expanded(
              child: _messages.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        return _FernBubble(
                          message: _messages[index],
                          isMine: _messages[index].role == 'user',
                        );
                      },
                    ),
            ),
            _buildInputBar(primary, surface),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalModelBanner() {
    final progress = _downloadProgress;
    return Material(
      color: fernLilac.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const AppIcon(AppIcons.bot, size: 18, color: fernLilac),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _downloadingModel
                        ? 'Downloading local AI model…'
                        : 'Run Fern on this device (no cloud)',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_downloadingModel)
                  Text(
                    progress == null
                        ? ''
                        : '${(progress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 13),
                  )
                else
                  TextButton(
                    onPressed: _downloadModel,
                    child: const Text('Download'),
                  ),
              ],
            ),
            if (_downloadingModel && progress != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: fernLilac.withValues(alpha: 0.15),
                  valueColor: const AlwaysStoppedAnimation<Color>(fernLilac),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppIcon(AppIcons.bot, size: 42, color: fernLilac),
            const SizedBox(height: 12),
            Text(
              'Say hi to Fern',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Fern is a local AI assistant. Your conversation stays on this '
              'device and is gone when you log out or uninstall the app.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(Color primary, Color surface) {
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
                controller: _controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(
                  hintText: 'Message Fern',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Send',
              onPressed: _sending ? null : _send,
              style: IconButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: primary.withValues(alpha: 0.4),
              ),
              icon: _sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const AppIcon(AppIcons.sendHorizontal, size: 20, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class _FernBubble extends StatelessWidget {
  const _FernBubble({required this.message, required this.isMine});

  final FernMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: BoxDecoration(
          color: isMine ? Colors.black : const Color(0xFFF2F2F2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          message.content,
          style: TextStyle(
            color: isMine ? Colors.white : const Color(0xFF1A1A1A),
            fontSize: 15,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}
