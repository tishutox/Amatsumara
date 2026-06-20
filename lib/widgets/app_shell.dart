import 'dart:async';
import 'dart:math' as math;

import 'package:lumii_quest/core/responsive/breakpoints.dart';
import 'package:lumii_quest/core/theme/app_theme.dart';
import 'package:lumii_quest/core/update/apk_update.dart';
import 'package:lumii_quest/features/chats/presentation/chats_page.dart';
import 'package:lumii_quest/features/communities/presentation/communities_page.dart';
import 'package:lumii_quest/features/home/presentation/home_page.dart';
import 'package:lumii_quest/features/me/presentation/me_page.dart';
import 'package:flutter/material.dart';
import 'package:remixicon/remixicon.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum SystemColorMode { light, dark, hellaverse, glitch }

class _SystemPalette {
  const _SystemPalette({
    required this.navColor,
    required this.backgroundColor,
    required this.brightness,
  });

  final Color navColor;
  final Color backgroundColor;
  final Brightness brightness;
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const String _colorModePrefKey = 'system_color_mode';
  static const double _maxContentWidth = 1160;

  int _currentIndex = 0;
  int? _hoveredCompactIndex;
  bool _hasShownUpdateHint = false;
  SystemColorMode _colorMode = SystemColorMode.light;
  late final StreamSubscription<AuthState> _authSubscription;

  static const _titles = ['Discover', 'Communities', 'Chats', 'Me'];
  static const _labels = ['Discover', 'Communities', 'Chats', 'Me'];
  static const _lineIcons = [
    Remix.compass_line,
    Remix.collage_line,
    Remix.message_3_line,
    Remix.account_circle_line,
  ];
  static const _fillIcons = [
    Remix.compass_fill,
    Remix.collage_fill,
    Remix.message_3_fill,
    Remix.account_circle_fill,
  ];

  static const Map<SystemColorMode, _SystemPalette> _palettes = {
    SystemColorMode.light: _SystemPalette(
      navColor: Color(0xFF5860C3),
      backgroundColor: Color(0xFFFFFFFF),
      brightness: Brightness.light,
    ),
    SystemColorMode.dark: _SystemPalette(
      navColor: Color(0xFF5860C3),
      backgroundColor: Color(0xFF121212),
      brightness: Brightness.dark,
    ),
    SystemColorMode.hellaverse: _SystemPalette(
      navColor: Color(0xFFF90142),
      backgroundColor: Color(0xFF121212),
      brightness: Brightness.dark,
    ),
    SystemColorMode.glitch: _SystemPalette(
      navColor: Color(0xFFDB5DC9),
      backgroundColor: Color(0xFF121212),
      brightness: Brightness.dark,
    ),
  };

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
      selected ? _fillIcons[index] : _lineIcons[index],
      color: selected ? navColor : navColor.withValues(alpha: 0.72),
    );
    final avatarUrl = _avatarUrl;
    if (index != 3 || avatarUrl == null) {
      return fallback;
    }

    return SizedBox.square(
      dimension: 24,
      child: Image.network(
        avatarUrl,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }

  Future<void> _loadSavedColorMode() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString(_colorModePrefKey);
    if (savedMode == null) {
      return;
    }

    SystemColorMode? matchingMode;
    for (final mode in SystemColorMode.values) {
      if (mode.name == savedMode) {
        matchingMode = mode;
        break;
      }
    }

    if (matchingMode == null || !mounted) {
      return;
    }

    final selectedMode = matchingMode;
    setState(() => _colorMode = selectedMode);
  }

  Future<void> _setColorMode(SystemColorMode mode) async {
    setState(() => _colorMode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_colorModePrefKey, mode.name);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_hasShownUpdateHint) {
      return;
    }
    _hasShownUpdateHint = true;

    Future<void>.delayed(const Duration(seconds: 3), () {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: const Text(
            'A new version is available. Download the APK directly.',
          ),
          action: SnackBarAction(
            label: 'Download',
            onPressed: () => ApkUpdate.openLatestApk(context),
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < Breakpoints.compact;
    final isExpanded = width >= Breakpoints.expanded;
    final palette = _palettes[_colorMode]!;
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
          title: Text(_titles[_currentIndex]),
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
                        // Uses the same s-line family shape as arrow-down-s-line.
                        icon: Transform.rotate(
                          angle: math.pi,
                          child: Icon(
                            Remix.arrow_up_s_line,
                            color: navColor,
                            size: 18,
                          ),
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
