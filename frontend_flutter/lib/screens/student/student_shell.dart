import 'package:flutter/material.dart';

import 'attendance_screen.dart';
import 'leaderboard_screen.dart';
import 'menu_screen.dart';
import 'rewards_screen.dart';
import 'student_dashboard.dart';

class StudentShell extends StatefulWidget {
  const StudentShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<StudentShell> createState() => _StudentShellState();
}

class _StudentShellState extends State<StudentShell> {
  late int _selectedIndex;
  late final List<int> _pageVersions;

  static const List<_StudentDestination> _destinations = [
    _StudentDestination('Home', Icons.home_rounded, Icons.home_outlined),
    _StudentDestination(
      'Menu',
      Icons.restaurant_menu_rounded,
      Icons.restaurant_menu_outlined,
    ),
    _StudentDestination(
      'Attendance',
      Icons.check_circle_rounded,
      Icons.check_circle_outline_rounded,
    ),
    _StudentDestination(
      'Rewards',
      Icons.card_giftcard_rounded,
      Icons.card_giftcard_outlined,
    ),
    _StudentDestination(
      'Rank',
      Icons.emoji_events_rounded,
      Icons.emoji_events_outlined,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageVersions = List<int>.filled(5, 0);
    _selectedIndex = widget.initialIndex.clamp(0, _pageVersions.length - 1);
  }

  void _selectTab(int index) {
    if (!mounted) return;
    setState(() {
      _selectedIndex = index;
      _pageVersions[index] = _pageVersions[index] + 1;
    });
  }

  List<Widget> get _pages => [
    StudentDashboard(
      key: ValueKey('student-home-${_pageVersions[0]}'),
      onOpenMenu: () => _selectTab(1),
      onOpenAttendance: () => _selectTab(2),
      onOpenRewards: () => _selectTab(3),
      onOpenLeaderboard: () => _selectTab(4),
    ),
    MenuScreen(key: ValueKey('student-menu-${_pageVersions[1]}')),
    AttendanceScreen(
      key: ValueKey('student-attendance-${_pageVersions[2]}'),
      onOpenMenu: () => _selectTab(1),
    ),
    RewardsScreen(key: ValueKey('student-rewards-${_pageVersions[3]}')),
    LeaderboardScreen(key: ValueKey('student-rank-${_pageVersions[4]}')),
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

class _StudentDestination {
  const _StudentDestination(this.label, this.selectedIcon, this.icon);

  final String label;
  final IconData selectedIcon;
  final IconData icon;
}
