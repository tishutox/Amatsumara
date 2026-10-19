import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lumii_quest/core/routing/profile_links.dart';
import 'package:lumii_quest/core/theme/saved_app_theme.dart';
import 'package:lumii_quest/features/friends/data/friend_repository.dart';
import 'package:lumii_quest/features/friends/domain/relationship_status.dart';
import 'package:lumii_quest/features/profile/data/profile_repository.dart';
import 'package:lumii_quest/features/profile/domain/user_profile.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class PublicProfilePage extends StatefulWidget {
  const PublicProfilePage({required this.username, super.key});

  final String username;

  @override
  State<PublicProfilePage> createState() => _PublicProfilePageState();
}

class _PublicProfilePageState extends State<PublicProfilePage> {
  late Future<UserProfile?> _profile;
  UserProfile? _resolvedProfile;
  final _friendRepository = FriendRepository();
  RelationshipStatus _relationshipStatus = RelationshipStatus.signedOut;
  bool _relationshipBusy = false;

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
    _resolvedProfile = null;
    _profile = ProfileRepository().getByUsername(widget.username);
    _profile.then((profile) {
      if (!mounted) return;
      setState(() => _resolvedProfile = profile);
      if (profile != null) _loadRelationship(profile);
    });
  }

  Future<void> _loadRelationship(UserProfile profile) async {
    try {
      final status = await _friendRepository.getStatus(profile.id);
      if (mounted && _resolvedProfile?.id == profile.id) {
        setState(() => _relationshipStatus = status);
      }
    } catch (_) {
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (mounted && currentUser != null && currentUser.id != profile.id) {
        setState(() => _relationshipStatus = RelationshipStatus.none);
      }
    }
  }

  Future<void> _handleRelationship() async {
    final profile = _resolvedProfile;
    if (profile == null || _relationshipBusy) return;

    if (_relationshipStatus == RelationshipStatus.incomingPending) {
      context.push('/notifications');
      return;
    }

    if (_relationshipStatus == RelationshipStatus.friends) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Unfriend this person?'),
          content: Text(
            'Are you sure you want to remove ${profile.displayName} from your friends?',
          ),
          actions: [
            TextButton(
              onPressed: () => context.pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => context.pop(true),
              child: const Text('Unfriend'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _relationshipBusy = true);
    try {
      if (_relationshipStatus == RelationshipStatus.friends) {
        await _friendRepository.unfriend(profile.id);
        if (mounted) {
          setState(() => _relationshipStatus = RelationshipStatus.none);
          _showMessage('Friend removed.');
        }
      } else if (_relationshipStatus == RelationshipStatus.none) {
        await _friendRepository.sendRequest(profile.id);
        if (mounted) {
          setState(
            () => _relationshipStatus = RelationshipStatus.outgoingPending,
          );
          _showMessage('Friend request sent.');
        }
      }
    } catch (error) {
      if (mounted) _showMessage('Friend action failed: $error');
    } finally {
      if (mounted) setState(() => _relationshipBusy = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final resolvedProfile = _resolvedProfile;
    final profileBackground = resolvedProfile?.backgroundColor;
    final profileAccent = resolvedProfile?.accentColor;
    return SavedAppTheme(
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: profileBackground,
          foregroundColor: profileAccent,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            onPressed: () => context.canPop() ? context.pop() : context.go('/'),
            icon: const Icon(LucideIcons.chevronLeft),
          ),
          actions: [
            if (_showsRelationshipAction)
              IconButton(
                tooltip: _relationshipTooltip,
                onPressed:
                    _relationshipBusy ||
                        _relationshipStatus ==
                            RelationshipStatus.outgoingPending
                    ? null
                    : _handleRelationship,
                icon: Icon(
                  _relationshipStatus == RelationshipStatus.friends
                      ? LucideIcons.userMinus
                      : LucideIcons.userPlus,
                ),
              ),
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
              icon: const Icon(LucideIcons.link),
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

  bool get _showsRelationshipAction {
    return _relationshipStatus != RelationshipStatus.signedOut &&
        _relationshipStatus != RelationshipStatus.self;
  }

  String get _relationshipTooltip => switch (_relationshipStatus) {
    RelationshipStatus.friends => 'Unfriend',
    RelationshipStatus.outgoingPending => 'Friend request sent',
    RelationshipStatus.incomingPending => 'Open friend request',
    _ => 'Send friend request',
  };
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
      colorScheme: baseTheme.colorScheme.copyWith(
        primary: profile.accentColor,
        surface: profile.backgroundColor,
        onSurface: foreground,
        surfaceContainer: profile.backgroundColor,
        surfaceContainerHigh: profile.backgroundColor,
        surfaceContainerHighest: profile.backgroundColor,
      ),
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
      popupMenuTheme: PopupMenuThemeData(
        color: profile.backgroundColor,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(color: foreground),
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
                              mention: profile.mentions.firstOrNull,
                              accentColor: profile.accentColor,
                            ),
                          ],
                        ),
                      ),
                      Transform.translate(
                        offset: const Offset(0, -18),
                        child: Padding(
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
                                        textAlign:
                                            profile.bioAlignment.textAlign,
                                        linkColor: profile.accentColor,
                                      ),
                                    ),
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
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileConnections extends StatelessWidget {
  const _ProfileConnections({required this.accentColor, this.mention});

  final ProfileMention? mention;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    if (mention == null) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
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
                  child: Icon(LucideIcons.image, size: 36, color: accentColor),
                )
              : Image.network(
                  url!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Center(
                    child: Icon(LucideIcons.image, size: 36, color: accentColor),
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
      child: Center(child: Icon(LucideIcons.userRound, color: accentColor)),
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
