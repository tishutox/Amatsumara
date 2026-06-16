import 'package:friendship/core/responsive/breakpoints.dart';
import 'package:friendship/core/update/apk_update.dart';
import 'package:friendship/features/chats/presentation/chats_page.dart';
import 'package:friendship/features/communities/presentation/communities_page.dart';
import 'package:friendship/features/home/presentation/home_page.dart';
import 'package:friendship/features/me/presentation/me_page.dart';
import 'package:flutter/material.dart';
import 'package:remixicon/remixicon.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;
  bool _hasShownUpdateHint = false;

  static const Color _circusRed = Color(0xFFEF372C);
  static const Color _circusBlue = Color(0xFF5860C3);

  static const _titles = ['Discover', 'Communities', 'Chats', 'Me'];
  static const _labels = ['Discover', 'Communities', 'Chats', 'Me'];
  static const _lineIcons = [
    Remix.compass_line,
    Remix.collage_line,
    Remix.chat_1_line,
    Remix.user_line,
  ];
  static const _fillIcons = [
    Remix.compass_fill,
    Remix.collage_fill,
    Remix.chat_1_fill,
    Remix.user_fill,
  ];

  static const _pages = [
    HomePage(),
    CommunitiesPage(),
    ChatsPage(),
    MePage(),
  ];

  Color _tabColor(int index) {
    return switch (index) {
      0 || 2 => _circusRed,
      _ => _circusBlue,
    };
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
          content: const Text('Neue Version verfuegbar? APK direkt laden.'),
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

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_currentIndex]),
        foregroundColor: _tabColor(_currentIndex),
      ),
      body: Row(
        children: [
          if (!isCompact)
            NavigationRail(
              selectedIndex: _currentIndex,
              extended: isExpanded,
              useIndicator: false,
              onDestinationSelected: (index) {
                setState(() => _currentIndex = index);
              },
              destinations: List<NavigationRailDestination>.generate(
                _labels.length,
                (index) => NavigationRailDestination(
                  icon: Icon(_lineIcons[index], color: _tabColor(index).withValues(alpha: 0.7)),
                  selectedIcon: Icon(_fillIcons[index], color: _tabColor(index)),
                  label: Text(
                    _labels[index],
                    style: TextStyle(color: _tabColor(index)),
                  ),
                ),
              ),
            ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: KeyedSubtree(
                key: ValueKey<int>(_currentIndex),
                child: _pages[_currentIndex],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: isCompact
          ? SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xFFE8ECEA))),
                ),
                child: Row(
                  children: List<Widget>.generate(
                    _labels.length,
                    (index) {
                      final isSelected = _currentIndex == index;
                      final color = _tabColor(index);
                      return Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setState(() => _currentIndex = index),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isSelected ? _fillIcons[index] : _lineIcons[index],
                                  color: isSelected ? color : color.withValues(alpha: 0.72),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _labels[index],
                                  style: TextStyle(
                                    color: isSelected ? color : color.withValues(alpha: 0.82),
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            )
          : null,
    );
  }
}
