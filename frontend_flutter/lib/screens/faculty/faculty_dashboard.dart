import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/campus_service.dart';
import '../../services/faculty_service.dart';
import '../auth/login_screen.dart';
import '../shared/profile_screen.dart';

class FacultyDashboard extends StatefulWidget {
  const FacultyDashboard({
    super.key,
    this.onOpenPayLater,
    this.onOpenAnalytics,
    this.onOpenProfile,
  });

  final VoidCallback? onOpenPayLater;
  final VoidCallback? onOpenAnalytics;
  final VoidCallback? onOpenProfile;

  @override
  State<FacultyDashboard> createState() => _FacultyDashboardState();
}

class _FacultyDashboardState extends State<FacultyDashboard>
    with TickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FacultyService _facultyService = FacultyService();
  final CampusService _campusService = CampusService();

  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  Map<String, dynamic> _userData = {};
  List<Map<String, dynamic>> _pendingOrders = [];
  List<Map<String, dynamic>> _menuPreview = [];
  int _pendingAmount = 0;
  int _menuCount = 0;
  bool _loading = true;
  bool _menuLoadFailed = false;
  bool _ordersLoadFailed = false;
  String? _loadMessage;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );
    _animationController.forward();
    _loadFacultyData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  int _readInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  String _formatCurrency(int amount) => 'Rs.$amount';

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Future<void> _openScreen(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (!mounted) return;
    await _loadFacultyData();
  }

  void _openPayLater() {
    widget.onOpenPayLater?.call();
  }

  void _openAnalytics() {
    widget.onOpenAnalytics?.call();
  }

  void _openProfile() {
    if (widget.onOpenProfile != null) {
      widget.onOpenProfile!();
      return;
    }
    _openScreen(const ProfileScreen());
  }

  Future<void> _loadFacultyData() async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _loadMessage = 'Sign in again to load the faculty dashboard.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _menuLoadFailed = false;
      _ordersLoadFailed = false;
      _loadMessage = null;
    });

    Map<String, dynamic> nextUserData = _userData;
    List<Map<String, dynamic>> nextPendingOrders = [];
    List<Map<String, dynamic>> nextMenuPreview = [];
    var nextPendingAmount = 0;
    var nextMenuCount = 0;
    var menuLoadFailed = false;
    var ordersLoadFailed = false;
    var profileLoadFailed = false;

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      nextUserData = userDoc.data() ?? <String, dynamic>{};
    } catch (_) {
      profileLoadFailed = true;
    }

    try {
      final menu = await _campusService.getMenu();
      nextMenuPreview = menu.take(4).toList();
      nextMenuCount = menu.length;
    } catch (_) {
      menuLoadFailed = true;
    }

    try {
      final summary = await _facultyService.getPendingSummary(
        facultyId: user.uid,
      );
      final orders = await _facultyService.getOrders(facultyId: user.uid);
      nextPendingAmount = _readInt(summary['total_pending']);
      nextPendingOrders = (orders['orders'] as List<dynamic>? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } catch (_) {
      ordersLoadFailed = true;
    }

    if (!mounted) return;
    setState(() {
      _userData = nextUserData;
      _pendingOrders = nextPendingOrders;
      _menuPreview = nextMenuPreview;
      _pendingAmount = nextPendingAmount;
      _menuCount = nextMenuCount;
      _menuLoadFailed = menuLoadFailed;
      _ordersLoadFailed = ordersLoadFailed;
      _loadMessage = profileLoadFailed
          ? 'Your faculty profile is temporarily unavailable. Pull to refresh and try again.'
          : null;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 980;
    final isPhone = width < 700;
    final displayName =
        (_userData['name']?.toString().trim().isNotEmpty ?? false)
        ? _userData['name'].toString().trim()
        : 'Faculty';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: SafeArea(
                child: RefreshIndicator(
                  onRefresh: _loadFacultyData,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      isPhone ? 16 : 20,
                      isPhone ? 16 : 20,
                      isPhone ? 16 : 20,
                      isPhone ? 112 : 32,
                    ),
                    children: [
                      _buildHeader(displayName),
                      SizedBox(height: isPhone ? 18 : 24),
                      _buildHeroCard(displayName, isPhone),
                      SizedBox(height: isPhone ? 18 : 24),
                      _buildMetricsGrid(isWide, isPhone),
                      SizedBox(height: isPhone ? 22 : 28),
                      _buildQuickActionsSection(isPhone),
                      if (_loadMessage != null) ...[
                        const SizedBox(height: 22),
                        _buildInfoBanner(_loadMessage!),
                      ],
                      SizedBox(height: isPhone ? 22 : 28),
                      _buildLiveSnapshotSection(isWide),
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

  Widget _buildHeader(String displayName) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F766E), Color(0xFF2563EB)],
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(
            Icons.school_rounded,
            color: Colors.white,
            size: 28,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Faculty Dashboard',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_greeting()}, $displayName',
                style: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFF475569),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: _loadFacultyData,
          style: IconButton.styleFrom(backgroundColor: Colors.white),
          icon: const Icon(Icons.refresh_rounded),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          tooltip: 'Profile options',
          icon: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
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
              final navigator = Navigator.of(context, rootNavigator: true);
              await AuthService().logout();
              if (!mounted) return;
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
      ],
    );
  }

  Widget _buildHeroCard(String displayName, bool isPhone) {
    final department = _userData['department']?.toString().trim();
    final subtitle = department != null && department.isNotEmpty
        ? '$displayName • $department'
        : displayName;

    return Container(
      padding: EdgeInsets.all(isPhone ? 20 : 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _heroBadge(
                _pendingAmount > 0 ? 'Payment pending' : 'No dues right now',
                _pendingAmount > 0
                    ? Icons.account_balance_wallet_rounded
                    : Icons.check_circle_rounded,
              ),
              _heroBadge(
                _menuLoadFailed
                    ? 'Menu sync delayed'
                    : '$_menuCount menu items live',
                Icons.restaurant_menu_rounded,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Review your canteen dues and keep an eye on campus food activity.',
            style: TextStyle(
              color: Colors.white,
              fontSize: isPhone ? 23 : 27,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFFE0F2FE),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: _openPayLater,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF0F766E),
                ),
                icon: const Icon(Icons.receipt_long_rounded),
                label: const Text('Open Pay-Later'),
              ),
              OutlinedButton.icon(
                onPressed: _openAnalytics,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white70),
                ),
                icon: const Icon(Icons.analytics_rounded),
                label: const Text('View Analytics'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroBadge(String label, IconData icon) {
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

  Widget _buildMetricsGrid(bool isWide, bool isPhone) {
    final cards = [
      _MetricCardData(
        'Pending amount',
        _formatCurrency(_pendingAmount),
        'Current canteen dues',
        Icons.account_balance_wallet_rounded,
        const Color(0xFF2563EB),
      ),
      _MetricCardData(
        'Pending orders',
        '${_pendingOrders.length}',
        'Orders waiting for payment',
        Icons.receipt_long_rounded,
        const Color(0xFF7C3AED),
      ),
      _MetricCardData(
        'Menu access',
        '$_menuCount items',
        'Approved items available for ordering',
        Icons.restaurant_menu_rounded,
        const Color(0xFF0F766E),
      ),
      _MetricCardData(
        'Faculty status',
        _ordersLoadFailed ? 'Needs refresh' : 'Live',
        'Backend summary and orders are connected',
        Icons.wifi_tethering_rounded,
        const Color(0xFFF97316),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cards.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isWide ? 4 : (isPhone ? 1 : 2),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: isPhone ? 1.65 : 1.25,
      ),
      itemBuilder: (context, index) => _buildMetricCard(cards[index], isPhone),
    );
  }

  Widget _buildMetricCard(_MetricCardData data, bool isPhone) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: data.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(data.icon, color: data.color),
          ),
          const SizedBox(height: 14),
          Text(
            data.title,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            data.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: const Color(0xFF0F172A),
              fontSize: isPhone ? 18 : 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          Text(
            data.caption,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsSection(bool isPhone) {
    final width = MediaQuery.sizeOf(context).width;
    final actions = [
      _QuickActionData(
        'Pay-Later',
        'Review menu and settle dues',
        Icons.receipt_long_rounded,
        const Color(0xFF2563EB),
        _openPayLater,
      ),
      _QuickActionData(
        'Campus Analytics',
        'See food usage and demand trends',
        Icons.analytics_rounded,
        const Color(0xFF7C3AED),
        _openAnalytics,
      ),
      _QuickActionData(
        'Profile',
        'Update your faculty details',
        Icons.person_rounded,
        const Color(0xFF0F766E),
        _openProfile,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          icon: Icons.flash_on_rounded,
          title: 'Quick Actions',
          color: const Color(0xFF2563EB),
        ),
        const SizedBox(height: 16),
        if (isPhone)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: actions.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: width < 600 ? 1 : 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              mainAxisExtent: 96,
            ),
            itemBuilder: (context, index) =>
                _buildQuickActionCard(actions[index]),
          )
        else
          SizedBox(
            height: 104,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: actions.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, index) =>
                  _buildQuickActionCard(actions[index]),
            ),
          ),
      ],
    );
  }

  Widget _buildQuickActionCard(_QuickActionData action) {
    return SizedBox(
      width: 220,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: action.onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: action.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(action.icon, color: action.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        action.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        action.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLiveSnapshotSection(bool isWide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          icon: Icons.insights_rounded,
          title: 'Live Snapshot',
          color: const Color(0xFF0F766E),
        ),
        const SizedBox(height: 16),
        if (isWide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildPendingOrdersCard()),
              const SizedBox(width: 16),
              Expanded(child: _buildMenuPreviewCard()),
            ],
          )
        else ...[
          _buildPendingOrdersCard(),
          const SizedBox(height: 16),
          _buildMenuPreviewCard(),
        ],
      ],
    );
  }

  Widget _buildPendingOrdersCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Pending Orders',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              TextButton(onPressed: _openPayLater, child: const Text('Open')),
            ],
          ),
          const SizedBox(height: 8),
          if (_loading && _pendingOrders.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_ordersLoadFailed)
            _buildInlineState(
              title: 'Pending orders are unavailable right now.',
              subtitle:
                  'The dashboard could not reach the faculty payment endpoints.',
              actionLabel: 'Retry',
              onPressed: _loadFacultyData,
            )
          else if (_pendingOrders.isEmpty)
            _buildInlineState(
              title: 'No pending faculty orders yet.',
              subtitle:
                  'Your canteen orders will appear here before settlement.',
              actionLabel: 'Browse pay-later menu',
              onPressed: _openPayLater,
            )
          else
            Column(
              children: _pendingOrders.take(4).map((order) {
                final items = (order['items'] as List<dynamic>? ?? const [])
                    .cast<Map>();
                final firstItem = items.isNotEmpty ? items.first : const {};
                final itemName =
                    firstItem['name']?.toString() ?? 'Faculty order';
                final quantity = _readInt(firstItem['quantity'], fallback: 1);
                final totalAmount = _readInt(order['total_amount']);
                final date = order['date']?.toString() ?? '';
                return Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF2563EB,
                          ).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.receipt_long_rounded,
                          color: Color(0xFF2563EB),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              itemName,
                              style: const TextStyle(
                                color: Color(0xFF0F172A),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Qty $quantity • ${_formatCurrency(totalAmount)}',
                              style: const TextStyle(
                                color: Color(0xFF475569),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (date.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  date,
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildMenuPreviewCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Approved Menu',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          if (_loading && _menuPreview.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_menuLoadFailed)
            _buildInlineState(
              title: 'Menu preview is unavailable right now.',
              subtitle: 'The dashboard could not fetch approved menu items.',
              actionLabel: 'Retry',
              onPressed: _loadFacultyData,
            )
          else if (_menuPreview.isEmpty)
            _buildInlineState(
              title: 'No approved menu items are visible yet.',
              subtitle:
                  'Once the canteen menu is approved, you can order from here.',
              actionLabel: 'Refresh',
              onPressed: _loadFacultyData,
            )
          else
            Column(
              children: _menuPreview.map((item) {
                final name = item['name']?.toString() ?? 'Menu item';
                final price = _readInt(item['price']);
                final category =
                    item['category']?.toString().toUpperCase() ?? 'GENERAL';
                return Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF0F766E,
                          ).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.restaurant_menu_rounded,
                          color: Color(0xFF0F766E),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                color: Color(0xFF0F172A),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              category,
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _formatCurrency(price),
                        style: const TextStyle(
                          color: Color(0xFF0F766E),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildInlineState({
    required String title,
    required String subtitle,
    required String actionLabel,
    required VoidCallback onPressed,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          TextButton(onPressed: onPressed, child: Text(actionLabel)),
        ],
      ),
    );
  }

  Widget _buildInfoBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFFB45309)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF92400E),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle({
    required IconData icon,
    required String title,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }
}

class _MetricCardData {
  const _MetricCardData(
    this.title,
    this.value,
    this.caption,
    this.icon,
    this.color,
  );

  final String title;
  final String value;
  final String caption;
  final IconData icon;
  final Color color;
}

class _QuickActionData {
  const _QuickActionData(
    this.title,
    this.subtitle,
    this.icon,
    this.color,
    this.onTap,
  );

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}
