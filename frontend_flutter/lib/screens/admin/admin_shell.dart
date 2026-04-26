import 'package:flutter/material.dart';

import 'admin_analytics_screen.dart';
import 'admin_dashboard.dart';
import 'menu_approval_screen.dart';
import 'user_management_screen.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  late int _selectedIndex;
  late final List<int> _pageVersions;

  static const List<_AdminDestination> _destinations = [
    _AdminDestination('Home', Icons.home_rounded, Icons.home_outlined),
    _AdminDestination(
      'Analytics',
      Icons.analytics_rounded,
      Icons.analytics_outlined,
    ),
    _AdminDestination(
      'Approvals',
      Icons.restaurant_rounded,
      Icons.restaurant_outlined,
    ),
    _AdminDestination('Users', Icons.group_rounded, Icons.group_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _pageVersions = List<int>.filled(_destinations.length, 0);
    _selectedIndex = widget.initialIndex.clamp(0, _destinations.length - 1);
  }

  void _selectTab(int index) {
    if (!mounted) return;
    setState(() {
      _selectedIndex = index;
      _pageVersions[index] = _pageVersions[index] + 1;
    });
  }

  List<Widget> get _pages => [
    AdminDashboard(key: ValueKey('admin-home-${_pageVersions[0]}')),
    AdminAnalyticsScreen(key: ValueKey('admin-analytics-${_pageVersions[1]}')),
    MenuApprovalScreen(key: ValueKey('admin-approvals-${_pageVersions[2]}')),
    UserManagementScreen(key: ValueKey('admin-users-${_pageVersions[3]}')),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      extendBody: true,
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _selectTab,
            height: 74,
            backgroundColor: Colors.white,
            indicatorColor: const Color(0xFFDFF3FF),
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: _destinations
                .map(
                  (destination) => NavigationDestination(
                    selectedIcon: Icon(destination.selectedIcon),
                    icon: Icon(destination.icon),
                    label: destination.label,
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }
}

class _AdminDestination {
  const _AdminDestination(this.label, this.selectedIcon, this.icon);

  final String label;
  final IconData selectedIcon;
  final IconData icon;
}
