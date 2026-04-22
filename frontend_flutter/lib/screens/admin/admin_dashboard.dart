import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/prediction_service.dart';
import '../auth/login_screen.dart';
import 'menu_upload_screen.dart';
import 'menu_approval_screen.dart';
import 'user_management_screen.dart';
import 'admin_waste_monitoring_screen.dart';
import 'food_exchange_requests_screen.dart';
import 'admin_analytics_screen.dart';
import 'login_attempts_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  final PredictionService _predictionService = PredictionService();

  Map<String, dynamic>? _mlOverviewData;
  bool _analyticsLoading = true;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
    
    _animationController.forward();
    _loadDashboardData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    setState(() {
      _analyticsLoading = true;
    });

    try {
      final mlOverview = await _predictionService.getMlOverview();
      if (!mounted) return;
      setState(() {
        _mlOverviewData = mlOverview;
        _analyticsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _analyticsLoading = false;
      });
    }
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  Color _statusColor(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.contains('running') || normalized.contains('progress')) {
      return const Color(0xFF3B82F6);
    }
    if (normalized.contains('strong') ||
        normalized.contains('promising') ||
        normalized.contains('reliable') ||
        normalized.contains('healthy') ||
        normalized.contains('success')) {
      return const Color(0xFF10B981);
    }
    if (normalized.contains('improving')) {
      return const Color(0xFF3B82F6);
    }
    if (normalized.contains('needs') ||
        normalized.contains('early') ||
        normalized.contains('failed')) {
      return const Color(0xFFF59E0B);
    }
    return const Color(0xFF6B7280);
  }

  String _formatTimestamp(dynamic value) {
    final raw = value?.toString() ?? '';
    if (raw.isEmpty) return 'Not available yet';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final local = parsed.toLocal();
    final monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final month = monthNames[local.month - 1];
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '${local.day} $month ${local.year}, $hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFF8F9FA), Color(0xFFE9ECEF)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    children: [
                      _buildModernHeader(context),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildQuickActionsSection(context),
                              const SizedBox(height: 32),
                              _buildMlImpactSection(),
                              const SizedBox(height: 32),
                              _buildTrainingStatusSection(context),
                              const SizedBox(height: 32),
                              _buildStatsOverview(),
                              const SizedBox(height: 32),
                              _buildManagementTools(isWide),
                              const SizedBox(height: 40),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // Modern Header Section
  Widget _buildModernHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4F46E5).withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.dashboard_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Admin Dashboard",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1F2937),
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  "CampusCurb Management System",
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFE5E7EB),
                width: 1,
              ),
            ),
            child: IconButton(
              icon: const Icon(
                Icons.logout_rounded, 
                color: Color(0xFF6B7280),
                size: 22,
              ),
              onPressed: () async {
                await AuthService().logout();
                if (!mounted) return;
                Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const LoginScreen()));
              },
            ),
          ),
        ],
      ),
    );
  }

  // Quick Actions Section
  Widget _buildQuickActionsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF4F46E5).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.flash_on_rounded,
                color: Color(0xFF4F46E5),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              "Quick Actions",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1F2937),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 130,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _buildModernQuickAction(context, "Add User", Icons.person_add_rounded, const Color(0xFF10B981), null),
              _buildModernQuickAction(context, "New Menu", Icons.add_circle_rounded, const Color(0xFF3B82F6), const MenuUploadScreen()),
              _buildModernQuickAction(context, "View Reports", Icons.assessment_rounded, const Color(0xFF8B5CF6), const AdminAnalyticsScreen()),
              _buildModernQuickAction(context, "Settings", Icons.settings_rounded, const Color(0xFFF59E0B), null),
              _buildModernQuickAction(context, "Help", Icons.help_rounded, const Color(0xFFEF4444), null),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMlImpactSection() {
    final impactSummary = Map<String, dynamic>.from(
      _mlOverviewData?['impact_summary'] as Map<String, dynamic>? ?? {},
    );
    final training = Map<String, dynamic>.from(
      _mlOverviewData?['training'] as Map<String, dynamic>? ?? {},
    );
    final accuracySummary = Map<String, dynamic>.from(
      _mlOverviewData?['accuracy_summary'] as Map<String, dynamic>? ?? {},
    );
    final operatorActions = List<String>.from(
      (_mlOverviewData?['operator_actions'] as List<dynamic>? ?? []).map(
        (item) => item.toString(),
      ),
    );

    if (_analyticsLoading) {
      return _buildSectionShell(
        icon: Icons.insights_rounded,
        title: 'ML Impact Snapshot',
        child: const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final headline = impactSummary['headline']?.toString() ??
        'ML impact will appear here after the forecasting engine and canteen logs sync.';
    final modelHealth = impactSummary['model_health']?.toString() ?? 'Not trained';
    final dataReadiness = impactSummary['data_readiness']?.toString() ?? 'Waiting for live data';

    return _buildSectionShell(
      icon: Icons.insights_rounded,
      title: 'ML Impact Snapshot',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0F766E), Color(0xFF2563EB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2563EB).withOpacity(0.15),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _buildStatusPill(modelHealth),
                _buildStatusPill(dataReadiness),
                _buildStatusPill(
                  '${_toDouble(accuracySummary['resolved_prediction_rate']).toStringAsFixed(1)}% resolved',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              headline,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildHighlightChip(
                  'Waste Saved',
                  '${_toInt(impactSummary['waste_saved_units'])}',
                ),
                _buildHighlightChip(
                  'Waste Reduction',
                  '${_toDouble(impactSummary['waste_reduction_percentage']).toStringAsFixed(1)}%',
                ),
                _buildHighlightChip(
                  'Best Model',
                  training['best_model_name']?.toString() ?? 'N/A',
                ),
                _buildHighlightChip(
                  'Best R²',
                  _toDouble(training['best_r2']).toStringAsFixed(2),
                ),
              ],
            ),
            if (operatorActions.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Text(
                'Immediate admin actions',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 10),
              ...operatorActions.take(2).map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.check_circle_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item,
                          style: const TextStyle(
                            color: Color(0xFFE0F2FE),
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTrainingStatusSection(BuildContext context) {
    final trainingStatus = Map<String, dynamic>.from(
      _mlOverviewData?['training_status'] as Map<String, dynamic>? ?? {},
    );

    if (_analyticsLoading) {
      return _buildSectionShell(
        icon: Icons.auto_graph_rounded,
        title: 'Training Status',
        child: const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final statusLabel =
        trainingStatus['status_label']?.toString() ?? 'Not started';
    final statusColor = _statusColor(statusLabel);

    return _buildSectionShell(
      icon: Icons.auto_graph_rounded,
      title: 'Training Status',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: statusColor.withOpacity(0.2)),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  'Last completed: ${_formatTimestamp(trainingStatus['last_completed_at'])}',
                  style: const TextStyle(
                    color: Color(0xFF4B5563),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildDashboardInfoChip(
                  'Best Model',
                  trainingStatus['best_model_name']?.toString() ?? 'Not trained',
                  const Color(0xFF3B82F6),
                ),
                _buildDashboardInfoChip(
                  'Dataset Rows',
                  '${_toInt(trainingStatus['dataset_rows'])}',
                  const Color(0xFF0F766E),
                ),
                _buildDashboardInfoChip(
                  'Live Rows Added',
                  '${_toInt(trainingStatus['live_rows_added'])}',
                  const Color(0xFF7C3AED),
                ),
                _buildDashboardInfoChip(
                  'Best R²',
                  _toDouble(trainingStatus['best_r2']).toStringAsFixed(2),
                  const Color(0xFF15803D),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Open the reports screen to run retraining, view recent runs, and inspect any failure details.',
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminAnalyticsScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Open Training Controls'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Stats Overview Section
  Widget _buildStatsOverview() {
    final impactSummary = Map<String, dynamic>.from(
      _mlOverviewData?['impact_summary'] as Map<String, dynamic>? ?? {},
    );
    final demandSummary = Map<String, dynamic>.from(
      _mlOverviewData?['demand_summary'] as Map<String, dynamic>? ?? {},
    );
    final accuracySummary = Map<String, dynamic>.from(
      _mlOverviewData?['accuracy_summary'] as Map<String, dynamic>? ?? {},
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(Icons.analytics_rounded, "Dashboard Overview"),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _buildModernStatCard(
                "Forecast Coverage",
                '${_toDouble(impactSummary['forecast_coverage_percentage']).toStringAsFixed(1)}%',
                Icons.track_changes_rounded,
                const Color(0xFF10B981),
                badgeLabel: '${_toInt(demandSummary['items_forecasted'])}/${_toInt(demandSummary['active_menu_items'])} items',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildModernStatCard(
                "Resolved Predictions",
                '${_toInt(accuracySummary['resolved_predictions'])}',
                Icons.verified_rounded,
                const Color(0xFF3B82F6),
                badgeLabel:
                    '${_toDouble(accuracySummary['resolved_prediction_rate']).toStringAsFixed(1)}% matched',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildModernStatCard(
                "Waste Saved",
                '${_toInt(impactSummary['waste_saved_units'])}',
                Icons.eco_rounded,
                const Color(0xFF8B5CF6),
                badgeLabel:
                    '${_toDouble(impactSummary['waste_reduction_percentage']).toStringAsFixed(1)}% reduction',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildModernStatCard(
                "Low Confidence Items",
                '${_toInt(demandSummary['low_confidence_count'])}',
                Icons.warning_amber_rounded,
                const Color(0xFFF59E0B),
                badgeLabel:
                    '${_toDouble(impactSummary['low_confidence_rate']).toStringAsFixed(1)}% risk',
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Management Tools Section
  Widget _buildManagementTools(bool isWide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF4F46E5).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.apps_rounded,
                color: Color(0xFF4F46E5),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              "Management Tools",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1F2937),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: 6,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: isWide ? 3 : 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: isWide ? 1.2 : 1.0,
          ),
          itemBuilder: (context, index) {
            final items = [
              {
                "title": "User Management",
                "subtitle": "Manage all users",
                "icon": Icons.group_rounded,
                "color": const Color(0xFF10B981),
                "screen": const UserManagementScreen()
              },
              {
                "title": "Menu Approvals",
                "subtitle": "Review & approve",
                "icon": Icons.restaurant_rounded,
                "color": const Color(0xFF3B82F6),
                "screen": const MenuApprovalScreen()
              },
              {
                "title": "Analytics",
                "subtitle": "View insights",
                "icon": Icons.analytics_rounded,
                "color": const Color(0xFF8B5CF6),
                "screen": const AdminAnalyticsScreen()
              },
              {
                "title": "Food Exchange",
                "subtitle": "Manage exchanges",
                "icon": Icons.swap_horiz_rounded,
                "color": const Color(0xFF4F46E5),
                "screen": const FoodExchangeRequestsScreen()
              },
              {
                "title": "Waste Tracking",
                "subtitle": "Monitor waste",
                "icon": Icons.delete_rounded,
                "color": const Color(0xFFF59E0B),
                "screen": const AdminWasteMonitoringScreen()
              },
              {
                "title": "Security Logs",
                "subtitle": "Login activity",
                "icon": Icons.security_rounded,
                "color": const Color(0xFF6B7280),
                "screen": const LoginAttemptsScreen()
              },
            ];

            final item = items[index];
            return _buildModernManagementCard(
              context,
              item["title"] as String,
              item["subtitle"] as String,
              item["icon"] as IconData,
              item["color"] as Color,
              item["screen"] as Widget,
            );
          },
        ),
      ],
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF4F46E5).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: const Color(0xFF4F46E5),
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1F2937),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionShell({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(icon, title),
        const SizedBox(height: 20),
        child,
      ],
    );
  }

  Widget _buildStatusPill(String label) {
    final color = _statusColor(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color == const Color(0xFF6B7280) ? Colors.white : color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildHighlightChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFE0F2FE),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardInfoChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // Modern Quick Action Card
  Widget _buildModernQuickAction(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    Widget? screen,
  ) {
    return Container(
      width: 100,
      margin: const EdgeInsets.only(right: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: screen == null
              ? null
              : () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => screen),
                  );
                },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: color.withOpacity(0.2),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: color,
                    size: 22,
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF374151),
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Modern Stat Card
  Widget _buildModernStatCard(
    String title,
    String value,
    IconData icon,
    Color color, {
    String? badgeLabel,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFE5E7EB),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 20,
                ),
              ),
              const Spacer(),
              if (badgeLabel != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    badgeLabel,
                    style: TextStyle(
                      fontSize: 10,
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1F2937),
            ),
          ),
        ],
      ),
    );
  }

  // Modern Management Card
  Widget _buildModernManagementCard(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    Color color,
    Widget screen,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => screen),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFE5E7EB),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.05),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: color.withOpacity(0.2),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(
                            icon,
                            color: color,
                            size: 32,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            color: color,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
