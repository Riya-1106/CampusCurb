import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/campus_service.dart';
import '../landing/landing_screen.dart';
import '../shared/profile_screen.dart';
import 'attendance_screen.dart';
import 'leaderboard_screen.dart';
import 'menu_screen.dart';
import 'rewards_screen.dart';

class StudentDashboard extends StatefulWidget {
  const StudentDashboard({
    super.key,
    this.onOpenMenu,
    this.onOpenAttendance,
    this.onOpenRewards,
    this.onOpenLeaderboard,
  });

  final VoidCallback? onOpenMenu;
  final VoidCallback? onOpenAttendance;
  final VoidCallback? onOpenRewards;
  final VoidCallback? onOpenLeaderboard;

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard>
    with TickerProviderStateMixin {
  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final CampusService _campusService = CampusService();

  Map<String, dynamic> _userData = {};
  List<Map<String, dynamic>> _menuPreview = [];
  List<Map<String, dynamic>> _recentOrders = [];

  int _totalOrders = 0;
  int _attendanceStreak = 0;
  int _rewardPoints = 0;
  int _totalSpent = 0;
  int _menuCount = 0;

  bool _isLoading = true;
  bool _hasMarkedToday = false;
  bool _menuLoadFailed = false;
  bool _ordersLoadFailed = false;
  bool _attendanceLoadFailed = false;
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
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _animationController.forward();
    _loadStudentData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  int _readInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = dateTime.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  String _formatShortDate(DateTime dateTime) {
    const months = [
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
    return '${dateTime.day} ${months[dateTime.month - 1]}';
  }

  String _formatHeaderDate(DateTime dateTime) {
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${weekdays[dateTime.weekday - 1]}, ${dateTime.day} ${months[dateTime.month - 1]}';
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _rewardLabel(int points) {
    if (points >= 500) return 'Free meal unlocked';
    if (points >= 250) return '10% discount active';
    if (points >= 100) return '5% discount active';
    return 'Build to your first reward';
  }

  String _nextRewardHint(int points) {
    if (points >= 500) return 'Top reward tier reached';
    if (points >= 250) return '${500 - points} points to a free meal';
    if (points >= 100) return '${250 - points} points to a 10% discount';
    return '${100 - points} points to your first discount';
  }

  String _titleCase(String value) {
    final cleaned = value.trim();
    if (cleaned.isEmpty) return 'General';
    return cleaned
        .split(RegExp(r'[_\s]+'))
        .map((word) {
          if (word.isEmpty) return word;
          return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
        })
        .join(' ');
  }

  Future<void> _openScreen(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (!mounted) return;
    await _loadStudentData();
  }

  void _openMenu() {
    if (widget.onOpenMenu != null) {
      widget.onOpenMenu!();
      return;
    }
    _openScreen(const MenuScreen());
  }

  void _openAttendance() {
    if (widget.onOpenAttendance != null) {
      widget.onOpenAttendance!();
      return;
    }
    _openScreen(const AttendanceScreen());
  }

  void _openRewards() {
    if (widget.onOpenRewards != null) {
      widget.onOpenRewards!();
      return;
    }
    _openScreen(const RewardsScreen());
  }

  void _openLeaderboard() {
    if (widget.onOpenLeaderboard != null) {
      widget.onOpenLeaderboard!();
      return;
    }
    _openScreen(const LeaderboardScreen());
  }

  Future<void> _loadStudentData() async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _isLoading = false;
        _loadMessage = 'Sign in again to load your student dashboard.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _loadMessage = null;
      _menuLoadFailed = false;
      _ordersLoadFailed = false;
      _attendanceLoadFailed = false;
    });

    var nextUserData = _userData;
    var nextRewardPoints = _rewardPoints;
    var nextAttendanceStreak = _attendanceStreak;
    var nextHasMarkedToday = _hasMarkedToday;
    var nextRecentOrders = _recentOrders;
    var nextMenuPreview = _menuPreview;
    var nextMenuCount = _menuCount;
    var nextTotalOrders = _totalOrders;
    var nextTotalSpent = _totalSpent;
    var nextAttendanceRecords = <Map<String, dynamic>>[];
    var nextAllOrders = <Map<String, dynamic>>[];

    var menuLoadFailed = false;
    var ordersLoadFailed = false;
    var attendanceLoadFailed = false;
    var profileLoadFailed = false;
    final cachedPoints = await _campusService.getCachedPoints(uid: user.uid);
    if (cachedPoints > nextRewardPoints) {
      nextRewardPoints = cachedPoints;
    }

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final userData = userDoc.data() ?? <String, dynamic>{};
      nextUserData = userData;
      final livePoints = _readInt(userData['points'] ?? userData['rewardPoints']);
      nextRewardPoints = livePoints > cachedPoints ? livePoints : cachedPoints;
    } catch (_) {
      profileLoadFailed = true;
    }

    try {
      final attendancePayload = await _campusService.getAttendanceHistory(
        uid: user.uid,
      );
      nextAttendanceStreak = _readInt(attendancePayload['current_streak']);
      nextHasMarkedToday = attendancePayload['has_marked_today'] == true;
      nextAttendanceRecords = (attendancePayload['records'] as List<dynamic>? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } catch (_) {
      attendanceLoadFailed = true;
    }

    try {
      final orders = await _campusService.getOrders(uid: user.uid);
      nextAllOrders = orders;
      final totalSpent = orders.fold<int>(
        0,
        (runningTotal, order) =>
            runningTotal +
            (_readInt(order['price']) *
                _readInt(order['quantity'], fallback: 1)),
      );
      nextRecentOrders = orders.take(4).toList();
      nextTotalOrders = orders.length;
      nextTotalSpent = totalSpent;
    } catch (_) {
      ordersLoadFailed = true;
      nextRecentOrders = [];
      nextTotalOrders = 0;
      nextTotalSpent = 0;
    }

    try {
      final menu = await _campusService.getMenu();
      nextMenuPreview = menu.take(4).toList();
      nextMenuCount = menu.length;
    } catch (_) {
      menuLoadFailed = true;
      nextMenuPreview = [];
      nextMenuCount = 0;
    }

    if (!ordersLoadFailed && !attendanceLoadFailed) {
      nextRewardPoints = _campusService.calculateRewardPoints(
        orders: nextAllOrders,
        attendanceRecords: nextAttendanceRecords,
      );
      await _campusService.cachePoints(
        uid: user.uid,
        points: nextRewardPoints,
      );
    }

    String? nextLoadMessage;
    if (profileLoadFailed && attendanceLoadFailed) {
      nextLoadMessage =
          'Your profile details are temporarily unavailable. Refresh to try again.';
    }

    if (!mounted) return;
    setState(() {
      _userData = nextUserData;
      _rewardPoints = nextRewardPoints;
      _attendanceStreak = nextAttendanceStreak;
      _hasMarkedToday = nextHasMarkedToday;
      _recentOrders = nextRecentOrders;
      _menuPreview = nextMenuPreview;
      _menuCount = nextMenuCount;
      _totalOrders = nextTotalOrders;
      _totalSpent = nextTotalSpent;
      _menuLoadFailed = menuLoadFailed;
      _ordersLoadFailed = ordersLoadFailed;
      _attendanceLoadFailed = attendanceLoadFailed;
      _loadMessage = nextLoadMessage;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 980;
    final isPhone = width < 700;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
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
                    colors: [Color(0xFFF5F7FB), Color(0xFFEFF6FF)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: SafeArea(
                  child: RefreshIndicator(
                    onRefresh: _loadStudentData,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        isPhone ? 16 : 20,
                        isPhone ? 16 : 20,
                        isPhone ? 16 : 20,
                        isPhone ? 112 : 32,
                      ),
                      children: [
                        _buildHeader(),
                        SizedBox(height: isPhone ? 18 : 24),
                        _buildHeroCard(isPhone),
                        SizedBox(height: isPhone ? 18 : 24),
                        _buildMetricsGrid(isWide, isPhone),
                        SizedBox(height: isPhone ? 22 : 28),
                        _buildQuickActionsSection(isPhone),
                        SizedBox(height: isPhone ? 22 : 28),
                        if (_loadMessage != null) ...[
                          _buildInfoBanner(_loadMessage!),
                          const SizedBox(height: 20),
                        ],
                        _buildLiveSnapshotSection(isWide),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader() {
    final displayName = (_userData['name']?.toString().trim().isNotEmpty ?? false)
        ? _userData['name'].toString().trim()
        : 'Student';

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F766E).withValues(alpha: 0.22),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(
            Icons.local_dining_rounded,
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
                'Student Dashboard',
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
          onPressed: _loadStudentData,
          style: IconButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF0F172A),
          ),
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
            child: const Icon(
              Icons.person_rounded,
              color: Color(0xFF475569),
            ),
          ),
          onSelected: (value) async {
            if (value == 'profile') {
              await _openScreen(const ProfileScreen());
              return;
            }

            if (value == 'logout') {
              final navigator = Navigator.of(context, rootNavigator: true);
              await AuthService().logout();
              if (!context.mounted) return;
              navigator.pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LandingScreen()),
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

  Widget _buildHeroCard(bool isPhone) {
    final now = DateTime.now();

    return Container(
      padding: EdgeInsets.all(isPhone ? 20 : 24),
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
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildHeroBadge(
                _attendanceLoadFailed
                    ? 'Attendance unavailable'
                    : _hasMarkedToday
                    ? 'Attendance marked'
                    : 'Attendance pending',
                _attendanceLoadFailed
                    ? Icons.info_outline_rounded
                    : _hasMarkedToday
                    ? Icons.check_circle_rounded
                    : Icons.pending_actions_rounded,
              ),
              _buildHeroBadge(
                _menuLoadFailed
                    ? 'Menu preview unavailable'
                    : '$_menuCount menu items live',
                Icons.restaurant_menu_rounded,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Plan the next meal without missing your rewards.',
            style: TextStyle(
              color: Colors.white,
              fontSize: isPhone ? 23 : 27,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${_formatHeaderDate(now)} • ${_rewardLabel(_rewardPoints)}',
            style: const TextStyle(
              color: Color(0xFFE0F2FE),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _nextRewardHint(_rewardPoints),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: _openMenu,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF0F766E),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                ),
                icon: const Icon(Icons.fastfood_rounded),
                label: const Text('Order Food'),
              ),
              OutlinedButton.icon(
                onPressed: _openRewards,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white70),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                ),
                icon: const Icon(Icons.card_giftcard_rounded),
                label: const Text('View Rewards'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroBadge(String label, IconData icon) {
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
    final metrics = [
      _MetricCardData(
        'Total Orders',
        _isLoading ? '...' : '$_totalOrders',
        'Account orders',
        Icons.shopping_bag_rounded,
        const Color(0xFF0F766E),
      ),
      _MetricCardData(
        'Total Spend',
        _isLoading ? '...' : '₹$_totalSpent',
        'Backend order total',
        Icons.payments_rounded,
        const Color(0xFF2563EB),
      ),
      _MetricCardData(
        'Attendance Streak',
        _isLoading ? '...' : '$_attendanceStreak days',
        _attendanceLoadFailed
            ? 'Attendance feed unavailable'
            : _hasMarkedToday
            ? 'Marked today'
            : 'Pending today',
        Icons.local_fire_department_rounded,
        const Color(0xFFF97316),
      ),
      _MetricCardData(
        'Reward Points',
        _isLoading ? '...' : '$_rewardPoints',
        'Current total',
        Icons.stars_rounded,
        const Color(0xFF7C3AED),
      ),
    ];

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
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.dashboard_customize_rounded,
                  color: Color(0xFF2563EB),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Today at a glance',
                      style: TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Read-only summary',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: isPhone ? 12 : 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: metrics.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: isWide ? 4 : 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              mainAxisExtent: isWide
                  ? 154
                  : isPhone
                  ? 156
                  : 152,
            ),
            itemBuilder: (context, index) => _buildMetricCard(
              metrics[index],
              isPhone: isPhone,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(_MetricCardData data, {required bool isPhone}) {
    return Container(
      padding: EdgeInsets.all(isPhone ? 12 : 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: data.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(data.icon, color: data.color, size: 18),
          ),
          const SizedBox(height: 12),
          Text(
            data.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Color(0xFF64748B),
              fontSize: isPhone ? 12 : 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            data.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: isPhone ? 17 : 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          Text(
            data.caption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Color(0xFF475569),
              fontSize: isPhone ? 11 : 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsSection(bool isPhone) {
    final actions = [
      _QuickActionData(
        'Order Food',
        'Browse menu',
        Icons.fastfood_rounded,
        const Color(0xFF0F766E),
        _openMenu,
      ),
      _QuickActionData(
        'Mark Attendance',
        'Keep the streak',
        Icons.check_circle_rounded,
        const Color(0xFF2563EB),
        _openAttendance,
      ),
      _QuickActionData(
        'Rewards',
        'Track benefits',
        Icons.card_giftcard_rounded,
        const Color(0xFF7C3AED),
        _openRewards,
      ),
      _QuickActionData(
        'Leaderboard',
        'See your rank',
        Icons.emoji_events_rounded,
        const Color(0xFFF97316),
        _openLeaderboard,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          icon: Icons.flash_on_rounded,
          title: 'Quick Actions',
          color: const Color(0xFF0F766E),
        ),
        const SizedBox(height: 16),
        if (isPhone)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: actions.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.12,
            ),
            itemBuilder: (context, index) => _buildQuickActionCard(actions[index]),
          )
        else
          SizedBox(
            height: 136,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: actions.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, index) => _buildQuickActionCard(actions[index]),
            ),
          ),
      ],
    );
  }

  Widget _buildQuickActionCard(_QuickActionData action) {
    return SizedBox(
      width: 190,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: action.onTap,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: action.color.withValues(alpha: 0.12),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: action.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(action.icon, color: action.color),
                ),
                const Spacer(),
                Text(
                  action.title,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  action.subtitle,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
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

  Widget _buildLiveSnapshotSection(bool isWide) {
    final children = [
      Expanded(child: _buildMenuPreviewCard()),
      const SizedBox(width: 16, height: 16),
      Expanded(child: _buildRecentOrdersCard()),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          icon: Icons.insights_rounded,
          title: 'Live Snapshot',
          color: const Color(0xFF2563EB),
        ),
        const SizedBox(height: 16),
        if (isWide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          )
        else
          Column(
            children: [
              _buildMenuPreviewCard(),
              const SizedBox(height: 16),
              _buildRecentOrdersCard(),
            ],
          ),
      ],
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
          Row(
            children: [
              const Expanded(
                child: Text(
                  "Today's Menu",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _openScreen(const MenuScreen()),
                child: const Text('See all'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_isLoading && _menuPreview.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_menuLoadFailed)
            _buildInlineState(
              title: 'Menu preview is unavailable right now.',
              subtitle: 'The dashboard could not reach the live menu feed.',
              actionLabel: 'Open Menu',
              onPressed: () => _openScreen(const MenuScreen()),
            )
          else if (_menuPreview.isEmpty)
            _buildInlineState(
              title: 'No approved menu items are visible yet.',
              subtitle: 'Once the canteen menu is approved, it will appear here.',
              actionLabel: 'Refresh',
              onPressed: _loadStudentData,
            )
          else
            Column(
              children: _menuPreview.map((item) {
                final category = _titleCase(item['category']?.toString() ?? 'general');
                final price = _readInt(item['price']);
                final itemName = item['name']?.toString() ?? 'Menu item';
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
                          color: const Color(0xFF0F766E).withValues(alpha: 0.12),
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
                              itemName,
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '₹$price',
                            style: const TextStyle(
                              color: Color(0xFF0F766E),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextButton(
                            onPressed: () => _openScreen(
                              MenuScreen(initialSearchQuery: itemName),
                            ),
                            child: const Text('Open'),
                          ),
                        ],
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

  Widget _buildRecentOrdersCard() {
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
            'Recent Orders',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          if (_isLoading && _recentOrders.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_ordersLoadFailed)
            _buildInlineState(
              title: 'Recent orders are unavailable right now.',
              subtitle: 'The dashboard could not fetch your order history.',
              actionLabel: 'Browse Menu',
              onPressed: () => _openScreen(const MenuScreen()),
            )
          else if (_recentOrders.isEmpty)
            _buildInlineState(
              title: 'Your orders will appear here after you place them.',
              subtitle: 'Start with the menu to create your first order.',
              actionLabel: 'Order Food',
              onPressed: () => _openScreen(const MenuScreen()),
            )
          else
            Column(
              children: _recentOrders.map((order) {
                final quantity = _readInt(order['quantity'], fallback: 1);
                final unitPrice = _readInt(order['price']);
                final total = quantity * unitPrice;
                final time = _parseDateTime(order['time']);
                final itemName = order['item']?.toString() ?? 'Order';

                return Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB).withValues(alpha: 0.12),
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
                              'Qty $quantity • ₹$total',
                              style: const TextStyle(
                                color: Color(0xFF475569),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (time != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                '${_formatShortDate(time)} • ${_formatTime(time)}',
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                            const SizedBox(height: 6),
                            TextButton.icon(
                              onPressed: () => _openScreen(
                                MenuScreen(initialSearchQuery: itemName),
                              ),
                              icon: const Icon(Icons.refresh_rounded, size: 16),
                              label: const Text('Order again'),
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
