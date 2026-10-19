import 'dart:async';

import 'package:lumii_quest/core/responsive/breakpoints.dart';
import 'package:lumii_quest/core/theme/app_theme.dart';
import 'package:lumii_quest/core/theme/saved_app_theme.dart';
import 'package:lumii_quest/features/chats/presentation/chats_page.dart';
import 'package:lumii_quest/features/communities/presentation/communities_page.dart';
import 'package:lumii_quest/features/home/presentation/home_page.dart';
import 'package:lumii_quest/features/me/presentation/me_page.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const double _maxContentWidth = 1160;

  int _currentIndex = 0;
  int? _hoveredCompactIndex;
  SystemColorMode _colorMode = SystemColorMode.light;
  late final StreamSubscription<AuthState> _authSubscription;

  static const _labels = ['Discover', 'Communities', 'Chats', 'Me'];
  static const _icons = [
    LucideIcons.compass,
    LucideIcons.layoutGridCircles,
    LucideIcons.messageCircle,
    LucideIcons.circleUserRound,
  ];

  List<Widget> _buildPages(Color navColor) {
    return [
      HomePage(navIconColor: navColor),
      const CommunitiesPage(),
      const ChatsPage(),
      const MePage(),
    ];
  }

  String _modeLabel(SystemColorMode mode) {
    switch (mode) {
      case SystemColorMode.light:
        return 'Light';
      case SystemColorMode.dark:
        return 'Dark';
      case SystemColorMode.hellaverse:
        return 'Hellaverse';
      case SystemColorMode.glitch:
        return 'Glitch';
    }
  }

  @override
  void initState() {
    super.initState();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      _,
    ) {
      if (mounted) {
        setState(() {});
      }
    });
    _loadSavedColorMode();
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  String? get _avatarUrl {
    final value =
        Supabase.instance.client.auth.currentUser?.userMetadata?['avatar_url'];
    return value is String && value.isNotEmpty ? value : null;
  }

  Widget _navigationIcon({
    required int index,
    required bool selected,
    required Color navColor,
  }) {
    final fallback = Icon(
      _icons[index],
      color: selected ? navColor : navColor.withValues(alpha: 0.72),
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

  Future<void> _loadSavedColorMode() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString(systemColorModePrefKey);
    if (savedMode == null) {
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() => _colorMode = systemColorModeFromName(savedMode));
  }

  Future<void> _setColorMode(SystemColorMode mode) async {
    setState(() => _colorMode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(systemColorModePrefKey, mode.name);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < Breakpoints.compact;
    final isExpanded = width >= Breakpoints.expanded;
    final palette = systemPalettes[_colorMode]!;
    final navColor = palette.navColor;
    final backgroundColor = palette.backgroundColor;
    final pages = _buildPages(navColor);
    final theme = AppTheme.system(
      primary: navColor,
      background: backgroundColor,
      brightness: palette.brightness,
    );

    return Theme(
      data: theme,
      child: Scaffold(
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
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 18, bottom: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: navColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: navColor.withValues(alpha: 0.24)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonHideUnderline(
                      child: DropdownButton<SystemColorMode>(
                        value: _colorMode,
                        borderRadius: BorderRadius.circular(12),
                        dropdownColor: backgroundColor,
                        icon: Icon(
                          LucideIcons.chevronDown,
                          color: navColor,
                          size: 18,
                        ),
                        iconEnabledColor: navColor,
                        style: TextStyle(
                          color: navColor,
                          fontWeight: FontWeight.w600,
                        ),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          _setColorMode(value);
                        },
                        items: SystemColorMode.values
                            .map(
                              (mode) => DropdownMenuItem<SystemColorMode>(
                                value: mode,
                                child: Text(_modeLabel(mode)),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
                        top: BorderSide(
                          color: navColor.withValues(alpha: 0.24),
                        ),
                      ),
                    ),
                    child: Row(
                      children: List<Widget>.generate(_labels.length, (index) {
                        final isSelected = _currentIndex == index;
                        final isHovered = _hoveredCompactIndex == index;
                        return Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            overlayColor:
                                WidgetStateProperty.resolveWith<Color?>((
                                  states,
                                ) {
                                  if (states.contains(WidgetState.pressed)) {
                                    return navColor.withValues(alpha: 0.18);
                                  }
                                  if (states.contains(WidgetState.hovered)) {
                                    return navColor.withValues(alpha: 0.10);
                                  }
                                  return null;
                                }),
                            onTap: () => setState(() => _currentIndex = index),
                            onHover: (value) {
                              setState(
                                () =>
                                    _hoveredCompactIndex = value ? index : null,
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
      ),
    );
  }
}
