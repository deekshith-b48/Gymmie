import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/l10n/l10n.dart';

/// Bottom navigation (phones) / navigation rail (tablets, like the original's collapsible sidebar).
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  static const _tabs = <(IconData, IconData, String)>[
    (Icons.home_outlined, Icons.home, 'Home'),
    (Icons.groups_2_outlined, Icons.groups_2, 'Members'),
    (Icons.insights_outlined, Icons.insights, 'Reports'),
    (Icons.receipt_long_outlined, Icons.receipt_long, 'Transactions'),
    (Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    void go(int i) => navigationShell.goBranch(
      i,
      initialLocation: i == navigationShell.currentIndex,
    );
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              extended: MediaQuery.sizeOf(context).width >= 1100,
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: go,
              destinations: [
                for (final t in _tabs)
                  NavigationRailDestination(
                    icon: Icon(t.$1),
                    selectedIcon: Icon(t.$2),
                    label: Text(t.$3.tr),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: navigationShell),
          ],
        ),
      );
    }
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: go,
        destinations: [
          for (final t in _tabs)
            NavigationDestination(
              icon: Icon(t.$1),
              selectedIcon: Icon(t.$2),
              label: t.$3.tr,
            ),
        ],
      ),
    );
  }
}

/// Placeholder shown while a tab's feature is still loading.
class TabPlaceholder extends StatelessWidget {
  const TabPlaceholder(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: const Center(child: CircularProgressIndicator()),
  );
}
