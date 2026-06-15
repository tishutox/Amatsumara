import 'package:friendship/core/responsive/breakpoints.dart';
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

  static const _titles = ['Discover', 'Communities', 'Chats', 'Me'];

  static const _pages = [
    HomePage(),
    CommunitiesPage(),
    ChatsPage(),
    MePage(),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < Breakpoints.compact;
    final isExpanded = width >= Breakpoints.expanded;

    return Scaffold(
      appBar: AppBar(title: Text(_titles[_currentIndex])),
      body: Row(
        children: [
          if (!isCompact)
            NavigationRail(
              selectedIndex: _currentIndex,
              extended: isExpanded,
              onDestinationSelected: (index) {
                setState(() => _currentIndex = index);
              },
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Remix.compass_line),
                  selectedIcon: Icon(Remix.compass_fill),
                  label: Text('Discover'),
                ),
                NavigationRailDestination(
                  icon: Icon(Remix.collage_line),
                  selectedIcon: Icon(Remix.collage_fill),
                  label: Text('Communities'),
                ),
                NavigationRailDestination(
                  icon: Icon(Remix.chat_1_line),
                  selectedIcon: Icon(Remix.chat_1_fill),
                  label: Text('Chats'),
                ),
                NavigationRailDestination(
                  icon: Icon(Remix.user_line),
                  selectedIcon: Icon(Remix.user_fill),
                  label: Text('Me'),
                ),
              ],
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
          ? NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) {
                setState(() => _currentIndex = index);
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Remix.compass_line),
                  selectedIcon: Icon(Remix.compass_fill),
                  label: 'Discover',
                ),
                NavigationDestination(
                  icon: Icon(Remix.collage_line),
                  selectedIcon: Icon(Remix.collage_fill),
                  label: 'Communities',
                ),
                NavigationDestination(
                  icon: Icon(Remix.chat_1_line),
                  selectedIcon: Icon(Remix.chat_1_fill),
                  label: 'Chats',
                ),
                NavigationDestination(
                  icon: Icon(Remix.user_line),
                  selectedIcon: Icon(Remix.user_fill),
                  label: 'Me',
                ),
              ],
            )
          : null,
    );
  }
}
