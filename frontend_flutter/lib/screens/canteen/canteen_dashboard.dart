import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../auth/login_screen.dart';
import '../shared/profile_screen.dart';
import 'analytics_screen.dart';
import 'inventory_screen.dart';
import 'menu_upload_screen.dart';
import 'prediction_screen.dart';
import 'waste_screen.dart';

class CanteenDashboard extends StatelessWidget {
  const CanteenDashboard({super.key});

  void _openScreen(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  Widget _heroPill(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricCard(String title, String subtitle, IconData icon, Color accent) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String footer,
    required IconData icon,
    required Color accent,
    required Widget screen,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openScreen(context, screen),
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: accent,
                          size: 20,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        footer,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: accent,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        title: const Text(
          'Canteen Dashboard',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('No notifications')),
              );
            },
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          PopupMenuButton<String>(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Icon(Icons.person_rounded, color: Color(0xFF475569)),
            ),
            onSelected: (value) async {
              if (value == 'profile') {
                _openScreen(context, const ProfileScreen());
                return;
              }
              if (value == 'logout') {
                final navigator = Navigator.of(context);
                await AuthService().logout();
                if (!context.mounted) return;
                navigator.pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: 'profile',
                child: Row(
                  children: [
                    Icon(Icons.person_outline_rounded),
                    SizedBox(width: 10),
                    Text('Profile'),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded),
                    SizedBox(width: 10),
                    Text('Logout'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0F766E), Color(0xFF2563EB)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.18),
                    blurRadius: 24,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: Colors.white,
                        child: Icon(Icons.restaurant_rounded, color: Color(0xFF0F766E)),
                      ),
                      SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Canteen Management',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Plan, publish, and track food operations in one place.',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 15,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _heroPill('Live menu sync', Icons.sync_rounded),
                      _heroPill('Operations log', Icons.receipt_long_rounded),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _metricCard(
                    'Menu items live',
                    'Published to student menu',
                    Icons.restaurant_menu_rounded,
                    const Color(0xFF2563EB),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _metricCard(
                    'Operations',
                    'Prepared / sold / wasted',
                    Icons.inventory_2_rounded,
                    const Color(0xFF0F766E),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _metricCard(
                    'Forecasts',
                    'Prep planning',
                    Icons.trending_up_rounded,
                    const Color(0xFF7C3AED),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _metricCard(
                    'Waste',
                    'Loss tracking',
                    Icons.delete_outline_rounded,
                    const Color(0xFFF97316),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.flash_on_rounded,
                    color: Color(0xFF2563EB),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Dashboard Actions',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (isWide)
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                mainAxisExtent: 122,
                children: [
                  _actionCard(
                    context,
                    title: 'Upload Menu',
                    subtitle: 'Publish items students can order today.',
                    footer: 'Add / edit live menu',
                    icon: Icons.restaurant_menu_rounded,
                    accent: const Color(0xFF2563EB),
                    screen: const MenuUploadScreen(),
                  ),
                  _actionCard(
                    context,
                    title: 'Operations Log',
                    subtitle: 'Record prepared, sold, and wasted counts.',
                    footer: 'Track service totals',
                    icon: Icons.inventory_2_outlined,
                    accent: const Color(0xFF0F766E),
                    screen: const InventoryScreen(),
                  ),
                  _actionCard(
                    context,
                    title: 'Demand Forecast',
                    subtitle: 'See what to prep next from live demand.',
                    footer: 'Plan tomorrow’s prep',
                    icon: Icons.trending_up_rounded,
                    accent: const Color(0xFF7C3AED),
                    screen: const PredictionScreen(),
                  ),
                  _actionCard(
                    context,
                    title: 'Waste Report',
                    subtitle: 'Review losses and spot food waste trends.',
                    footer: 'Check waste patterns',
                    icon: Icons.delete_outline_rounded,
                    accent: const Color(0xFFF97316),
                    screen: const WasteScreen(),
                  ),
                  _actionCard(
                    context,
                    title: 'Analytics',
                    subtitle: 'Measure canteen performance and activity.',
                    footer: 'Open performance view',
                    icon: Icons.analytics_rounded,
                    accent: const Color(0xFF14B8A6),
                    screen: const AnalyticsScreen(),
                  ),
                ],
              )
            else
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                mainAxisExtent: 126,
                children: [
                  _actionCard(
                    context,
                    title: 'Upload Menu',
                    subtitle: 'Publish items students can order today.',
                    footer: 'Add / edit live menu',
                    icon: Icons.restaurant_menu_rounded,
                    accent: const Color(0xFF2563EB),
                    screen: const MenuUploadScreen(),
                  ),
                  _actionCard(
                    context,
                    title: 'Operations Log',
                    subtitle: 'Record prepared, sold, and wasted counts.',
                    footer: 'Track service totals',
                    icon: Icons.inventory_2_outlined,
                    accent: const Color(0xFF0F766E),
                    screen: const InventoryScreen(),
                  ),
                  _actionCard(
                    context,
                    title: 'Demand Forecast',
                    subtitle: 'See what to prep next from live demand.',
                    footer: 'Plan tomorrow’s prep',
                    icon: Icons.trending_up_rounded,
                    accent: const Color(0xFF7C3AED),
                    screen: const PredictionScreen(),
                  ),
                  _actionCard(
                    context,
                    title: 'Waste Report',
                    subtitle: 'Review losses and spot food waste trends.',
                    footer: 'Check waste patterns',
                    icon: Icons.delete_outline_rounded,
                    accent: const Color(0xFFF97316),
                    screen: const WasteScreen(),
                  ),
                  _actionCard(
                    context,
                    title: 'Analytics',
                    subtitle: 'Measure canteen performance and activity.',
                    footer: 'Open performance view',
                    icon: Icons.analytics_rounded,
                    accent: const Color(0xFF14B8A6),
                    screen: const AnalyticsScreen(),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
