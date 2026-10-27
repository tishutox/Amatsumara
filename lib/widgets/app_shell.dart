import 'dart:async';

import 'package:lumii_quest/core/responsive/breakpoints.dart';
import 'package:lumii_quest/features/calls/data/call_signaling.dart';
import 'package:lumii_quest/features/chats/presentation/chats_page.dart';
import 'package:lumii_quest/features/communities/presentation/communities_page.dart';
import 'package:lumii_quest/features/home/presentation/home_page.dart';
import 'package:lumii_quest/features/me/presentation/own_profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const double _maxContentWidth = 1160;

  static const Color _navColor = Color(0xFFE26E83);
  static const Color _backgroundColor = Color(0xFF161518);

  int _currentIndex = 0;
  int _profileReloadCount = 0;
  int? _hoveredCompactIndex;
  late final StreamSubscription<AuthState> _authSubscription;
  RealtimeChannel? _incomingCallChannel;

  static const _labels = ['Discover', 'Communities', 'Chats', 'Me'];
  static const _icons = [
    LucideIcons.compass,
    LucideIcons.layoutGridCircles,
    LucideIcons.messagesCircle,
    LucideIcons.circleUserRound,
  ];

  List<Widget> _buildPages(Color navColor) {
    return [
      HomePage(navIconColor: navColor),
      const CommunitiesPage(),
      const ChatsPage(),
      OwnProfilePage(reloadCount: _profileReloadCount),
    ];
  }

  @override
  void initState() {
    super.initState();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      _,
    ) {
      if (mounted) {
        setState(() {});
        _syncIncomingCallListener();
      }
    });
    _syncIncomingCallListener();
  }

  void _syncIncomingCallListener() {
    _incomingCallChannel?.unsubscribe();
    _incomingCallChannel = null;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      return;
    }
    _incomingCallChannel = CallSignaling().subscribeIncoming(
      userId,
      _onIncomingCall,
    );
  }

  void _onIncomingCall(Map<String, dynamic> payload) {
    if (payload['type'] != 'ring' || !mounted) {
      return;
    }
    final from = payload['from'] as String?;
    if (from == null || from.isEmpty) {
      return;
    }
    final name = payload['name'] as String? ?? 'Lumii user';
    final avatar = payload['avatarUrl'] as String?;
    context.push(
      Uri(
        path: '/call/$from',
        queryParameters: {
          'name': name,
          if (avatar != null && avatar.isNotEmpty) 'avatar': avatar,
          'incoming': 'true',
        },
      ).toString(),
    );
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    _incomingCallChannel?.unsubscribe();
    super.dispose();
  }

  String? get _avatarUrl {
    final value =
        Supabase.instance.client.auth.currentUser?.userMetadata?['avatar_url'];
    return value is String && value.isNotEmpty ? value : null;
  }

  String? get _username {
    final value =
        Supabase.instance.client.auth.currentUser?.userMetadata?['username'];
    return value is String && value.isNotEmpty ? value : null;
  }

  Future<void> _editProfile() async {
    await context.push<bool>('/edit-profile');
    if (mounted) setState(() => _profileReloadCount++);
  }

  Future<void> _copyProfileLink() async {
    await Clipboard.setData(
      ClipboardData(text: 'https://tishutox.github.io/Lumii/app/u/$_username'),
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile link copied.')));
    }
  }

  Widget _navigationIcon({
    required int index,
    required bool selected,
    required Color navColor,
  }) {
    final fallback = Icon(
      _icons[index],
      color: selected ? navColor : const Color(0xFFA29FA3),
    );
    final avatarUrl = _avatarUrl;
    if (index != 3 || avatarUrl == null) {
      return fallback;
    }

    return Center(
      widthFactor: 1,
      heightFactor: 1,
      child: SizedBox.square(
        dimension: 24,
        child: ClipOval(
          child: Image.network(
            avatarUrl,
            width: 24,
            height: 24,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => fallback,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < Breakpoints.compact;
    final isExpanded = width >= Breakpoints.expanded;
    const navColor = _navColor;
    const backgroundColor = _backgroundColor;
    final pages = _buildPages(navColor);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        titleSpacing: 8,
        title: IconButton(
          tooltip: 'Notifications',
          onPressed: () => context.push('/notifications'),
          icon: const Icon(LucideIcons.bell),
        ),
        foregroundColor: navColor,
        backgroundColor: backgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (_username != null) ...[
            if (_currentIndex == 3) ...[
              IconButton(
                tooltip: 'Copy profile link',
                onPressed: _copyProfileLink,
                icon: const Icon(LucideIcons.link),
              ),
              IconButton(
                tooltip: 'Edit profile',
                onPressed: _editProfile,
                icon: const Icon(LucideIcons.pencilRuler),
              ),
            ] else ...[
              IconButton(
                tooltip: 'Friends list',
                onPressed: () => context.push('/friends'),
                icon: const Icon(LucideIcons.bookHeart),
              ),
              IconButton(
                tooltip: 'Settings',
                onPressed: () => context.push('/settings'),
                icon: const Icon(LucideIcons.bolt),
              ),
            ],
          ],
          const SizedBox(width: 8),
        ],
      ),

      body: Row(
        children: [
          if (!isCompact)
            Theme(
              data: Theme.of(context).copyWith(
                hoverColor: navColor.withValues(alpha: 0.10),
                splashColor: navColor.withValues(alpha: 0.14),
                highlightColor: navColor.withValues(alpha: 0.08),
              ),
              child: NavigationRail(
                backgroundColor: backgroundColor,
                selectedIndex: _currentIndex,
                extended: isExpanded,
                useIndicator: true,
                indicatorColor: navColor.withValues(alpha: 0.16),
                onDestinationSelected: (index) {
                  setState(() => _currentIndex = index);
                },
                destinations: List<NavigationRailDestination>.generate(
                  _labels.length,
                  (index) => NavigationRailDestination(
                    icon: _navigationIcon(
                      index: index,
                      selected: false,
                      navColor: navColor,
                    ),
                    selectedIcon: _navigationIcon(
                      index: index,
                      selected: true,
                      navColor: navColor,
                    ),
                    label: Text(
                      _labels[index],
                      style: TextStyle(color: navColor),
                    ),
                  ),
                ),
              ),
            ),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: KeyedSubtree(
                    key: ValueKey<int>(_currentIndex),
                    child: pages[_currentIndex],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: isCompact
          ? Theme(
              data: Theme.of(context).copyWith(
                hoverColor: navColor.withValues(alpha: 0.10),
                splashColor: navColor.withValues(alpha: 0.14),
                highlightColor: navColor.withValues(alpha: 0.08),
              ),
              child: SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    border: Border(
                      top: BorderSide(color: navColor.withValues(alpha: 0.24)),
                    ),
                  ),
                  child: Row(
                    children: List<Widget>.generate(_labels.length, (index) {
                      final isSelected = _currentIndex == index;
                      final isHovered = _hoveredCompactIndex == index;
                      return Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          overlayColor: WidgetStateProperty.resolveWith<Color?>(
                            (states) {
                              if (states.contains(WidgetState.pressed)) {
                                return navColor.withValues(alpha: 0.18);
                              }
                              if (states.contains(WidgetState.hovered)) {
                                return navColor.withValues(alpha: 0.10);
                              }
                              return null;
                            },
                          ),
                          onTap: () => setState(() => _currentIndex = index),
                          onHover: (value) {
                            setState(
                              () => _hoveredCompactIndex = value ? index : null,
                            );
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? navColor.withValues(alpha: 0.16)
                                  : isHovered
                                  ? navColor.withValues(alpha: 0.10)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _navigationIcon(
                                  index: index,
                                  selected: isSelected,
                                  navColor: navColor,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}
