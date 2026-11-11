import 'package:flutter/material.dart';

import 'communities_page.dart';
import 'explore_page.dart';
import 'my_page.dart';
import 'near_page.dart';
import 'rooms_page.dart';

/// ホーム: 近く / 部屋 / コミュニティ / 探す / マイページ（仕様書 8 章参照）
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          NearPage(),
          RoomsPage(),
          CommunitiesPage(),
          ExplorePage(),
          MyPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.near_me_outlined),
            selectedIcon: Icon(Icons.near_me),
            label: '近く',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: '部屋',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups),
            label: 'コミュニティ',
          ),
          NavigationDestination(
            icon: Icon(Icons.search),
            label: '探す',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'マイページ',
          ),
        ],
      ),
    );
  }
}
