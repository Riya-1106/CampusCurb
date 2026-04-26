import 'package:flutter/material.dart';

import '../shared/profile_screen.dart';
import 'analytics_screen.dart' as canteen_analytics;
import 'canteen_dashboard.dart';
import 'inventory_screen.dart';
import 'menu_upload_screen.dart';
import 'order_queue_screen.dart';
import 'prediction_screen.dart';
import 'waste_screen.dart';

class CanteenShell extends StatefulWidget {
  const CanteenShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<CanteenShell> createState() => _CanteenShellState();
}

class _CanteenShellState extends State<CanteenShell> {
  late int _selectedIndex;
  late final List<int> _pageVersions;
  late final List<bool> _loadedTabs;

  static const List<_CanteenDestination> _destinations = [
    _CanteenDestination('Home', Icons.home_rounded, Icons.home_outlined),
    _CanteenDestination(
      'Queue',
      Icons.receipt_long_rounded,
      Icons.receipt_long_outlined,
    ),
    _CanteenDestination(
      'Forecast',
      Icons.trending_up_rounded,
      Icons.trending_up_outlined,
    ),
    _CanteenDestination(
      'Menu',
      Icons.restaurant_menu_rounded,
      Icons.restaurant_menu_outlined,
    ),
    _CanteenDestination(
      'Analytics',
      Icons.analytics_rounded,
      Icons.analytics_outlined,
    ),
    _CanteenDestination(
      'Waste',
      Icons.delete_outline_rounded,
      Icons.delete_outline,
    ),
    _CanteenDestination(
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
    _loadedTabs = List<bool>.filled(_destinations.length, false);
    _loadedTabs[_selectedIndex] = true;
  }

  void _selectTab(int index) {
    if (!mounted) return;
    setState(() {
      _selectedIndex = index;
      _loadedTabs[index] = true;
    });
  }

  Future<void> _openOverlayScreen(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  Widget _buildPage(int index) {
    switch (index) {
      case 0:
        return CanteenDashboard(
          key: ValueKey('canteen-home-${_pageVersions[0]}'),
          onOpenQueue: () => _selectTab(1),
          onOpenForecast: () => _selectTab(2),
          onOpenOperations: () => _openOverlayScreen(const InventoryScreen()),
          onOpenMenuUpload: () => _selectTab(3),
          onOpenAnalytics: () => _selectTab(4),
          onOpenWaste: () => _selectTab(5),
          onOpenProfile: () => _selectTab(6),
        );
      case 1:
        return OrderQueueScreen(key: ValueKey('canteen-queue-${_pageVersions[1]}'));
      case 2:
        return PredictionScreen(key: ValueKey('canteen-forecast-${_pageVersions[2]}'));
      case 3:
        return MenuUploadScreen(key: ValueKey('canteen-menu-${_pageVersions[3]}'));
      case 4:
        return canteen_analytics.AnalyticsScreen(
          key: ValueKey('canteen-analytics-${_pageVersions[4]}'),
        );
      case 5:
        return WasteScreen(key: ValueKey('canteen-waste-${_pageVersions[5]}'));
      case 6:
      default:
        return ProfileScreen(key: ValueKey('canteen-profile-${_pageVersions[6]}'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      extendBody: true,
      body: IndexedStack(
        index: _selectedIndex,
        children: List<Widget>.generate(
          _destinations.length,
          (index) => _loadedTabs[index]
              ? _buildPage(index)
              : const SizedBox.shrink(),
        ),
      ),
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

class _CanteenDestination {
  const _CanteenDestination(this.label, this.selectedIcon, this.icon);

  final String label;
  final IconData selectedIcon;
  final IconData icon;
}
