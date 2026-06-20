import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lumii_quest/features/profile/data/profile_repository.dart';
import 'package:lumii_quest/features/profile/domain/user_profile.dart';
import 'package:remixicon/remixicon.dart';
import 'package:url_launcher/url_launcher.dart';

class PublicProfilePage extends StatefulWidget {
  const PublicProfilePage({required this.username, super.key});

  final String username;

  @override
  State<PublicProfilePage> createState() => _PublicProfilePageState();
}

class _PublicProfilePageState extends State<PublicProfilePage> {
  late Future<UserProfile?> _profile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PublicProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.username != widget.username) {
      _load();
    }
  }

  void _load() {
    _profile = ProfileRepository().getByUsername(widget.username);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
          icon: const Icon(Remix.arrow_left_line),
        ),
        title: Text('@${widget.username}'),
        actions: [
          IconButton(
            tooltip: 'Copy profile link',
            onPressed: () async {
              final link =
                  'https://tishutox.github.io/Lumii/app/u/${widget.username}';
              await Clipboard.setData(ClipboardData(text: link));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Profile link copied.')),
                );
              }
            },
            icon: const Icon(Remix.link),
          ),
        ],
      ),
      body: FutureBuilder<UserProfile?>(
        future: _profile,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ProfileMessage(
              message: 'This profile could not be loaded.',
              onRetry: () => setState(_load),
            );
          }
          final profile = snapshot.data;
          if (profile == null) {
            return const _ProfileMessage(message: 'Profile not found.');
          }
          return _ProfileContent(profile: profile);
        },
      ),
    );
  }
}

class _ProfileContent extends StatelessWidget {
  const _ProfileContent({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Banner(url: profile.bannerUrl),
                Transform.translate(
                  offset: const Offset(0, -48),
                  child: Column(
                    children: [
                      _Avatar(url: profile.avatarUrl, size: 96),
                      const SizedBox(height: 12),
                      Text(
                        profile.displayName,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text('@${profile.username}'),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (profile.bio.isNotEmpty)
                        _BioText(
                          text: profile.bio,
                          textAlign: profile.bioAlignment.textAlign,
                        ),
                      if (profile.links.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            for (final link in profile.links)
                              ActionChip(
                                avatar: const Icon(Remix.link, size: 16),
                                label: Text(link.label),
                                onPressed: () => _openUrl(link.url),
                              ),
                          ],
                        ),
                      ],
                      if (profile.mentions.isNotEmpty) ...[
                        const SizedBox(height: 26),
                        Text(
                          'People',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (final mention in profile.mentions)
                              ActionChip(
                                avatar: _Avatar(
                                  url: mention.avatarUrl,
                                  size: 24,
                                ),
                                label: Text(
                                  '${mention.tag} · @${mention.username}',
                                ),
                                onPressed: () =>
                                    context.push('/u/${mention.username}'),
                              ),
                          ],
                        ),
                      ],
                    ],
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

class _Banner extends StatelessWidget {
  const _Banner({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary.withValues(alpha: 0.16);
    return AspectRatio(
      aspectRatio: 3.2,
      child: ColoredBox(
        color: color,
        child: url == null
            ? const Center(child: Icon(Remix.image_line, size: 36))
            : Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const Center(child: Icon(Remix.image_line, size: 36)),
              ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.size, this.url});

  final double size;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.16),
      child: const Center(child: Icon(Remix.user_line)),
    );
    return SizedBox.square(
      dimension: size,
      child: ClipOval(
        child: url == null
            ? fallback
            : Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

class _BioText extends StatefulWidget {
  const _BioText({required this.text, required this.textAlign});

  final String text;
  final TextAlign textAlign;

  @override
  State<_BioText> createState() => _BioTextState();
}

class _BioTextState extends State<_BioText> {
  final List<TapGestureRecognizer> _recognizers = [];
  late List<InlineSpan> _spans;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(covariant _BioText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _disposeRecognizers();
      _parse();
    }
  }

  void _parse() {
    final pattern = RegExp(
      r'\(([^\)]+)\)\[([^\]]+)\]|\[([^\]]+)\]\(([^\)]+)\)',
    );
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in pattern.allMatches(widget.text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: widget.text.substring(cursor, match.start)));
      }
      final label = match.group(1) ?? match.group(3) ?? '';
      final url = match.group(2) ?? match.group(4) ?? '';
      final recognizer = TapGestureRecognizer()..onTap = () => _openUrl(url);
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.blue,
            decoration: TextDecoration.underline,
          ),
          recognizer: recognizer,
        ),
      );
      cursor = match.end;
    }
    if (cursor < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(cursor)));
    }
    _spans = spans;
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
        children: _spans,
      ),
      textAlign: widget.textAlign,
    );
  }
}

class _ProfileMessage extends StatelessWidget {
  const _ProfileMessage({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ],
      ),
    );
  }
}

Future<void> _openUrl(String value) async {
  final uri = Uri.tryParse(value);
  if (uri == null || !{'http', 'https'}.contains(uri.scheme)) {
    return;
  }
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
