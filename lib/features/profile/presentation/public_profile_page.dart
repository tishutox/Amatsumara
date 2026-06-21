import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lumii_quest/core/routing/profile_links.dart';
import 'package:lumii_quest/core/theme/saved_app_theme.dart';
import 'package:lumii_quest/features/profile/data/profile_repository.dart';
import 'package:lumii_quest/features/profile/domain/user_profile.dart';
import 'package:lumii_quest/features/profile/domain/social_platform.dart';
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
    return SavedAppTheme(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: () => context.canPop() ? context.pop() : context.go('/'),
            icon: const Icon(Remix.arrow_left_s_line),
          ),
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
      ),
    );
  }
}

class _ProfileContent extends StatelessWidget {
  const _ProfileContent({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final foreground = profile.backgroundColor.computeLuminance() > 0.48
        ? const Color(0xFF17171B)
        : const Color(0xFFF7F5FA);
    final baseTheme = Theme.of(context);
    final profileTheme = baseTheme.copyWith(
      textTheme: baseTheme.textTheme.apply(
        bodyColor: foreground,
        displayColor: foreground,
      ),
      iconTheme: IconThemeData(color: profile.accentColor),
      chipTheme: baseTheme.chipTheme.copyWith(
        backgroundColor: profile.accentColor.withValues(alpha: 0.12),
        selectedColor: profile.accentColor.withValues(alpha: 0.18),
        labelStyle: TextStyle(color: foreground),
        side: BorderSide(color: profile.accentColor.withValues(alpha: 0.45)),
      ),
    );

    return ColoredBox(
      color: profile.backgroundColor,
      child: Theme(
        data: profileTheme,
        child: DefaultTextStyle.merge(
          style: TextStyle(color: foreground),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                        child: _Banner(
                          url: profile.bannerUrl,
                          accentColor: profile.accentColor,
                        ),
                      ),
                      Transform.translate(
                        offset: const Offset(0, -48),
                        child: Column(
                          children: [
                            _Avatar(
                              url: profile.avatarUrl,
                              size: 106,
                              borderColor: profile.backgroundColor,
                              borderWidth: 5,
                              accentColor: profile.accentColor,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              profile.displayName,
                              style: profileTheme.textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 10),
                            _ProfileConnections(
                              links: profile.links,
                              mention: profile.mentions.firstOrNull,
                              accentColor: profile.accentColor,
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (profile.bio.isNotEmpty)
                              Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 620,
                                  ),
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: _BioText(
                                      text: profile.bio,
                                      textAlign: profile.bioAlignment.textAlign,
                                      linkColor: profile.accentColor,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileConnections extends StatelessWidget {
  const _ProfileConnections({
    required this.links,
    required this.accentColor,
    this.mention,
  });

  final List<ProfileLink> links;
  final ProfileMention? mention;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final socials = sortedProfileLinks(links);
    if (socials.isEmpty && mention == null) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PopupMenuButton<ProfileLink>(
          enabled: socials.isNotEmpty,
          tooltip: 'Socials',
          onSelected: (link) => _activateSocial(context, link),
          itemBuilder: (_) => [
            for (final link in socials)
              PopupMenuItem(
                value: link,
                child: Row(
                  children: [
                    Icon(link.platform.icon, size: 19, color: accentColor),
                    const SizedBox(width: 10),
                    Text(
                      link.platform == SocialPlatform.legacy
                          ? link.label
                          : '${link.platform.label} · ${link.username}',
                    ),
                  ],
                ),
              ),
          ],
          child: _ConnectionLabel(
            icon: Remix.link,
            label: 'Socials',
            accentColor: accentColor,
          ),
        ),
        if (mention != null) ...[
          Container(
            width: 1,
            height: 28,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            color: accentColor.withValues(alpha: 0.42),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => context.push('/u/${mention!.username}'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Avatar(
                    url: mention!.avatarUrl,
                    size: 24,
                    accentColor: accentColor,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    mention!.tag,
                    style: TextStyle(
                      color: accentColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ConnectionLabel extends StatelessWidget {
  const _ConnectionLabel({
    required this.icon,
    required this.label,
    required this.accentColor,
  });

  final IconData icon;
  final String label;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: accentColor),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(color: accentColor, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.accentColor, this.url});

  final String? url;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final color = accentColor.withValues(alpha: 0.16);
    return AspectRatio(
      aspectRatio: 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: ColoredBox(
          color: color,
          child: url == null
              ? Center(
                  child: Icon(Remix.image_line, size: 36, color: accentColor),
                )
              : Image.network(
                  url!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Center(
                    child: Icon(Remix.image_line, size: 36, color: accentColor),
                  ),
                ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.size,
    required this.accentColor,
    this.url,
    this.borderColor,
    this.borderWidth = 0,
  });

  final double size;
  final String? url;
  final Color accentColor;
  final Color? borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: accentColor.withValues(alpha: 0.16),
      child: Center(child: Icon(Remix.user_line, color: accentColor)),
    );
    return SizedBox.square(
      dimension: size,
      child: Container(
        padding: EdgeInsets.all(borderWidth),
        decoration: BoxDecoration(color: borderColor, shape: BoxShape.circle),
        child: ClipOval(
          child: url == null
              ? fallback
              : Image.network(
                  url!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => fallback,
                ),
        ),
      ),
    );
  }
}

class _BioText extends StatefulWidget {
  const _BioText({
    required this.text,
    required this.textAlign,
    required this.linkColor,
  });

  final String text;
  final TextAlign textAlign;
  final Color linkColor;

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
    if (oldWidget.text != widget.text ||
        oldWidget.linkColor != widget.linkColor) {
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
      final recognizer = TapGestureRecognizer()
        ..onTap = () => _openUrl(context, url);
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: label,
          style: TextStyle(
            color: widget.linkColor,
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

Future<void> _openUrl(BuildContext context, String value) async {
  final uri = Uri.tryParse(value);
  if (uri == null) {
    return;
  }
  final profileLocation = profileLocationFromUri(uri);
  if (profileLocation != null) {
    context.push(profileLocation);
    return;
  }
  if (!{'http', 'https'}.contains(uri.scheme)) {
    return;
  }
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<void> _activateSocial(BuildContext context, ProfileLink link) async {
  if (link.platform.copiesUsername) {
    await Clipboard.setData(ClipboardData(text: link.username));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Discord username copied.')));
    }
    return;
  }
  await _openUrl(context, link.url);
}
