import 'package:flutter/material.dart';

import '../shared/profile_screen.dart';
import 'analytics_screen.dart';
import 'faculty_dashboard.dart';
import 'pay_later_screen.dart';

class FacultyShell extends StatefulWidget {
  const FacultyShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<FacultyShell> createState() => _FacultyShellState();
}

class _FacultyShellState extends State<FacultyShell> {
  late int _selectedIndex;
  late final List<int> _pageVersions;

  static const List<_FacultyDestination> _destinations = [
    _FacultyDestination('Home', Icons.home_rounded, Icons.home_outlined),
    _FacultyDestination(
      'Pay-Later',
      Icons.receipt_long_rounded,
      Icons.receipt_long_outlined,
    ),
    _FacultyDestination(
      'Analytics',
      Icons.analytics_rounded,
      Icons.analytics_outlined,
    ),
    _FacultyDestination(
      'Profile',
      Icons.person_rounded,
      Icons.person_outline_rounded,
    ),
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
    FacultyDashboard(
      key: ValueKey('faculty-home-${_pageVersions[0]}'),
      onOpenPayLater: () => _selectTab(1),
      onOpenAnalytics: () => _selectTab(2),
      onOpenProfile: () => _selectTab(3),
    ),
    PayLaterScreen(key: ValueKey('faculty-paylater-${_pageVersions[1]}')),
    AnalyticsScreen(key: ValueKey('faculty-analytics-${_pageVersions[2]}')),
    ProfileScreen(key: ValueKey('faculty-profile-${_pageVersions[3]}')),
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

class _FacultyDestination {
  const _FacultyDestination(this.label, this.selectedIcon, this.icon);

  final String label;
  final IconData selectedIcon;
  final IconData icon;
}
