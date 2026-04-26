import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/prediction_service.dart';
import '../auth/login_screen.dart';
import '../shared/profile_screen.dart';

class CanteenDashboard extends StatefulWidget {
  const CanteenDashboard({
    super.key,
    this.onOpenMenuUpload,
    this.onOpenQueue,
    this.onOpenOperations,
    this.onOpenForecast,
    this.onOpenWaste,
    this.onOpenAnalytics,
    this.onOpenProfile,
  });

  final VoidCallback? onOpenMenuUpload;
  final VoidCallback? onOpenQueue;
  final VoidCallback? onOpenOperations;
  final VoidCallback? onOpenForecast;
  final VoidCallback? onOpenWaste;
  final VoidCallback? onOpenAnalytics;
  final VoidCallback? onOpenProfile;

  @override
  State<CanteenDashboard> createState() => _CanteenDashboardState();
}

class _CanteenDashboardState extends State<CanteenDashboard> {
  final PredictionService _predictionService = PredictionService();

  bool _loading = true;
  String? _errorMessage;
  bool _queueLoadFailed = false;
  bool _operationsLoadFailed = false;
  bool _wasteLoadFailed = false;
  bool _forecastLoadFailed = false;
  Map<String, dynamic> _operations = {};
  Map<String, dynamic> _waste = {};
  Map<String, dynamic> _forecast = {};
  Map<String, dynamic> _queueSummary = {};

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  int _readInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  String _timeSlotForNow() {
    final hour = DateTime.now().hour;
    if (hour < 11) return '09:00-11:00';
    if (hour < 13) return '11:00-13:00';
    if (hour < 15) return '13:00-15:00';
    return '15:00+';
  }

  List<String> _waitingSections() {
    final waiting = <String>[];
    if (_queueLoadFailed) waiting.add('Pickup Queue');
    if (_operationsLoadFailed) waiting.add('Operations');
    if (_wasteLoadFailed) waiting.add('Waste Report');
    if (_forecastLoadFailed) waiting.add('Demand Forecast');
    return waiting;
  }

  Future<void> _loadDashboardData() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
      _queueLoadFailed = false;
      _operationsLoadFailed = false;
      _wasteLoadFailed = false;
      _forecastLoadFailed = false;
    });

    try {
      final dateKey = _todayKey();
      final timeSlot = _timeSlotForNow();
      Future<Map<String, dynamic>> safeQueue() async {
        try {
          return await _predictionService.getCanteenOrderQueue();
        } catch (_) {
          _queueLoadFailed = true;
          return const {};
        }
      }

      Future<Map<String, dynamic>> safeOperations() async {
        try {
          return await _predictionService.getCanteenOperations(
            date: dateKey,
            timeSlot: timeSlot,
          );
        } catch (_) {
          _operationsLoadFailed = true;
          return const {};
        }
      }

      Future<Map<String, dynamic>> safeWaste() async {
        try {
          return await _predictionService.getWasteReport();
        } catch (_) {
          _wasteLoadFailed = true;
          return const {};
        }
      }

      Future<Map<String, dynamic>> safeForecast() async {
        try {
          return await _predictionService.getDemandDashboard(
            targetDate: dateKey,
            timeSlot: timeSlot,
          );
        } catch (_) {
          _forecastLoadFailed = true;
          return const {};
        }
      }

      final results = await Future.wait<Object>([
        safeQueue(),
        safeOperations(),
        safeWaste(),
        safeForecast(),
      ]);
      final queue = results[0] as Map<String, dynamic>;
      final operations = results[1] as Map<String, dynamic>;
      final waste = results[2] as Map<String, dynamic>;
      final forecast = results[3] as Map<String, dynamic>;
      final queueHasData =
          _readInt((queue['summary'] as Map<String, dynamic>?)?['total_orders']) >
          0;
      final operationsHasData = operations.isNotEmpty;
      final wasteHasData = waste.isNotEmpty;
      final forecastHasData = forecast.isNotEmpty;

      if (!mounted) return;
      setState(() {
        _queueSummary = Map<String, dynamic>.from(
          queue['summary'] as Map<String, dynamic>? ?? {},
        );
        _operations = operations;
        _waste = waste;
        _forecast = forecast;
        _queueLoadFailed = _queueLoadFailed && !queueHasData;
        _operationsLoadFailed = _operationsLoadFailed && !operationsHasData;
        _wasteLoadFailed = _wasteLoadFailed && !wasteHasData;
        _forecastLoadFailed = _forecastLoadFailed && !forecastHasData;
        if (_queueLoadFailed &&
            _operationsLoadFailed &&
            _wasteLoadFailed &&
            _forecastLoadFailed) {
          _errorMessage =
              'Canteen data is taking longer than expected right now. Pull to refresh in a moment.';
        }
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _openScreen(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (!mounted) return;
    await _loadDashboardData();
  }

  void _openProfile() {
    if (widget.onOpenProfile != null) {
      widget.onOpenProfile!();
      return;
    }
    _openScreen(const ProfileScreen());
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 980;

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
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadDashboardData,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Notifications',
            onPressed: () {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('No notifications')));
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
                _openProfile();
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? _buildErrorState()
          : RefreshIndicator(
              onRefresh: _loadDashboardData,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  if (_waitingSections().isNotEmpty) ...[
                    _buildInfoBanner(
                      'Waiting on: ${_waitingSections().join(', ')}. This screen is showing the sections that loaded first.',
                    ),
                    const SizedBox(height: 12),
                  ],
                  _buildHeroCard(),
                  const SizedBox(height: 14),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: width < 600 ? 1 : (isWide ? 4 : 2),
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    mainAxisExtent: width < 600 ? 96 : 118,
                    children: [
                      _metricCard(
                        'Pickup pending',
                        '${_readInt(_queueSummary['pending_count'])}',
                        'Orders waiting at counter',
                        Icons.receipt_long_rounded,
                        const Color(0xFF2563EB),
                      ),
                      _metricCard(
                        'Prepared today',
                        '${_readInt(_operations['summary']?['total_prepared'])}',
                        'Operations log total',
                        Icons.inventory_2_rounded,
                        const Color(0xFF0F766E),
                      ),
                      _metricCard(
                        'Forecast total',
                        '${_readInt(_forecast['summary']?['total_predicted_demand'])}',
                        'Predicted demand for active slot',
                        Icons.trending_up_rounded,
                        const Color(0xFF7C3AED),
                      ),
                      _metricCard(
                        'Waste rate',
                        _waste['Waste Percentage']?.toString() ?? '0%',
                        'Live waste report',
                        Icons.delete_outline_rounded,
                        const Color(0xFFF97316),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
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
                      const SizedBox(width: 8),
                      const Text(
                        'Dashboard Actions',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: width < 600 ? 1 : (isWide ? 3 : 2),
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    mainAxisExtent: width < 600 ? 96 : 100,
                    children: [
                      _actionCard(
                        title: 'Pickup Queue',
                        subtitle: 'Track live student and faculty tokens.',
                        footer: 'Open counter queue',
                        icon: Icons.receipt_long_rounded,
                        accent: const Color(0xFF2563EB),
                        onTap: widget.onOpenQueue,
                      ),
                      _actionCard(
                        title: 'Upload Menu',
                        subtitle: 'Send new items for admin approval.',
                        footer: 'Manage pending menu',
                        icon: Icons.restaurant_menu_rounded,
                        accent: const Color(0xFF0F766E),
                        onTap: widget.onOpenMenuUpload,
                      ),
                      _actionCard(
                        title: 'Operations Log',
                        subtitle: 'Record prepared, sold, and wasted totals.',
                        footer: 'Update service counts',
                        icon: Icons.inventory_2_outlined,
                        accent: const Color(0xFF2563EB),
                        onTap: widget.onOpenOperations,
                      ),
                      _actionCard(
                        title: 'Demand Forecast',
                        subtitle: 'Review the model suggestion for this slot.',
                        footer: 'Plan the next batch',
                        icon: Icons.trending_up_rounded,
                        accent: const Color(0xFF7C3AED),
                        onTap: widget.onOpenForecast,
                      ),
                      _actionCard(
                        title: 'Waste Report',
                        subtitle: 'See current waste and reduction impact.',
                        footer: 'Review food loss',
                        icon: Icons.delete_outline_rounded,
                        accent: const Color(0xFFF97316),
                        onTap: widget.onOpenWaste,
                      ),
                      _actionCard(
                        title: 'Analytics',
                        subtitle: 'Track demand, waste, and live behavior.',
                        footer: 'Open canteen insights',
                        icon: Icons.analytics_rounded,
                        accent: const Color(0xFF14B8A6),
                        onTap: widget.onOpenAnalytics,
                      ),
                      _actionCard(
                        title: 'Profile',
                        subtitle: 'Update canteen contact details.',
                        footer: 'Account settings',
                        icon: Icons.person_rounded,
                        accent: const Color(0xFF475569),
                        onTap: _openProfile,
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildErrorState() {
    return RefreshIndicator(
      onRefresh: _loadDashboardData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          _buildInfoBanner(_errorMessage!),
          const SizedBox(height: 14),
          _buildHeroCard(),
        ],
      ),
    );
  }

  Widget _buildInfoBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFFC2410C),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF9A3412),
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard() {
    final user = FirebaseAuth.instance.currentUser;
    return Container(
      padding: const EdgeInsets.all(18),
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _heroPill('Live menu sync', Icons.sync_rounded),
              _heroPill('Operations log', Icons.receipt_long_rounded),
              _heroPill(_timeSlotForNow(), Icons.schedule_rounded),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Plan service, publish items, and track how the live canteen is performing.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            user?.email ?? 'Signed-in canteen operator',
            style: const TextStyle(
              color: Color(0xFFE0F2FE),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroPill(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricCard(
    String title,
    String value,
    String subtitle,
    IconData icon,
    Color accent,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
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
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionCard({
    required String title,
    required String subtitle,
    required String footer,
    required IconData icon,
    required Color accent,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
          borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: accent,
                          size: 20,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        footer,
                        style: TextStyle(
                          color: accent,
                          fontSize: 10,
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
}
