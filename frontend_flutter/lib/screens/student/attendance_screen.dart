import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/campus_service.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final CampusService _service = CampusService();

  DateTime _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selectedDate;

  bool _isLoading = true;
  bool _isMarking = false;
  bool _hasMarkedToday = false;
  bool _isLocalMode = false;

  int _currentStreak = 0;
  int _monthlyAttendance = 0;
  double _attendancePercentage = 0;

  String? _errorMessage;
  String? _noticeMessage;
  List<Map<String, dynamic>> _attendanceHistory = [];

  int _readInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  double _readDouble(dynamic value, {double fallback = 0}) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  String _currentTime() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  String _formatDate(String rawDate) {
    final parsed = DateTime.tryParse(rawDate);
    if (parsed == null) return rawDate;
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
    return '${parsed.day} ${months[parsed.month - 1]} ${parsed.year}';
  }

  String _dateKeyFromDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  int _daysInMonth(DateTime month) {
    return DateTime(month.year, month.month + 1, 0).day;
  }

  bool _isFutureDate(DateTime date) {
    final today = DateTime.now();
    final normalizedToday = DateTime(today.year, today.month, today.day);
    final normalizedDate = DateTime(date.year, date.month, date.day);
    return normalizedDate.isAfter(normalizedToday);
  }

  String _monthLabel(DateTime month) {
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
    return '${months[month.month - 1]} ${month.year}';
  }

  Map<String, Map<String, dynamic>> get _attendanceByDate {
    final map = <String, Map<String, dynamic>>{};
    for (final record in _attendanceHistory) {
      final normalizedDate = _normalizeRecordDate(record['date']);
      if (normalizedDate == null || normalizedDate.isEmpty) continue;
      map[normalizedDate] = record;
    }
    return map;
  }

  String? _normalizeRecordDate(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) {
      return _dateKeyFromDate(parsed);
    }

    final match = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(raw);
    if (match == null) return raw;
    final year = match.group(1)!;
    final month = match.group(2)!.padLeft(2, '0');
    final day = match.group(3)!.padLeft(2, '0');
    return '$year-$month-$day';
  }

  Map<String, dynamic>? _recordForDate(DateTime date) {
    return _attendanceByDate[_dateKeyFromDate(date)];
  }

  void _changeMonth(int delta) {
    final nextMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta, 1);
    final currentSelection = _selectedDate;
    final selectedDay = currentSelection == null ? 1 : currentSelection.day;
    final boundedDay = selectedDay.clamp(1, _daysInMonth(nextMonth));

    setState(() {
      _visibleMonth = nextMonth;
      _selectedDate = DateTime(nextMonth.year, nextMonth.month, boundedDay);
    });
  }

  void _selectDate(DateTime date) {
    setState(() {
      _selectedDate = date;
    });
    HapticFeedback.selectionClick();
  }

  Future<void> _loadAttendanceData({bool preferLocalOnly = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Sign in again to use attendance.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _noticeMessage = null;
    });

    try {
      final payload = await _service.getAttendanceHistory(
        uid: user.uid,
        preferLocalOnly: preferLocalOnly,
      );
      final records = (payload['records'] as List<dynamic>? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      if (!mounted) return;
      setState(() {
        _attendanceHistory = records;
        _hasMarkedToday = payload['has_marked_today'] == true;
        _currentStreak = _readInt(payload['current_streak']);
        _monthlyAttendance = _readInt(payload['monthly_attendance']);
        _attendancePercentage = _readDouble(payload['attendance_percentage']);
        _isLocalMode = payload['is_local_fallback'] == true;
        _noticeMessage = payload['notice']?.toString();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _attendanceHistory = [];
        _currentStreak = 0;
        _monthlyAttendance = 0;
        _attendancePercentage = 0;
        _isLocalMode = false;
        _isLoading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _markAttendance() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (_hasMarkedToday) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Attendance already marked for today.')),
      );
      return;
    }

    setState(() {
      _isMarking = true;
    });

    try {
      final result = await _service.markAttendance(
        uid: user.uid,
        date: _todayKey(),
        time: _currentTime(),
      );

      if (!mounted) return;
      final pointsAwarded = _readInt(result['points_awarded']);
      final totalPoints = _readInt(result['total_points']);
      final isLocalFallback = result['is_local_fallback'] == true;
      final notice = result['notice']?.toString();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isLocalFallback
                ? 'Attendance saved on this device. Rewards will sync when the live server is reachable.'
                : pointsAwarded > 0
                ? 'Attendance marked. +$pointsAwarded points, total $totalPoints.'
                : 'Attendance marked successfully.',
          ),
        ),
      );
      HapticFeedback.lightImpact();
      if (notice != null && notice.isNotEmpty && mounted) {
        setState(() {
          _noticeMessage = notice;
          _isLocalMode = isLocalFallback;
        });
      }
      await _loadAttendanceData(preferLocalOnly: isLocalFallback);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isMarking = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _loadAttendanceData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        title: const Text('Attendance'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _loadAttendanceData,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAttendanceData,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          children: [
            _buildHeroCard(),
            const SizedBox(height: 18),
            if (_noticeMessage != null) ...[
              _buildNoticeBanner(_noticeMessage!),
              const SizedBox(height: 18),
            ],
            if (_errorMessage != null) ...[
              _buildErrorBanner(_errorMessage!),
              const SizedBox(height: 18),
            ],
            _buildMarkCard(),
          const SizedBox(height: 18),
          _buildStatsGrid(),
          const SizedBox(height: 18),
          _buildCalendarCard(),
          const SizedBox(height: 18),
          _buildHistoryCard(),
        ],
      ),
      ),
    );
  }

  Widget _buildHeroCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              _hasMarkedToday ? 'Marked for today' : 'Pending for today',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Track daily presence and keep your streak alive.',
            style: TextStyle(
              color: Colors.white,
              fontSize: _isLocalMode ? 22 : 24,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _hasMarkedToday
                ? 'You are already marked for today.'
                : 'Tap once below to mark attendance for today.',
            style: const TextStyle(
              color: Color(0xFFE0E7FF),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoticeBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.wifi_off_rounded, color: Color(0xFF2563EB)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF1D4ED8),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF991B1B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMarkCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Mark Attendance',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _hasMarkedToday
                ? 'Today is already recorded in your attendance log.'
                : 'Your attendance is recorded once per day and also adds reward points.',
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (_isMarking || _isLoading || _hasMarkedToday)
                  ? null
                  : _markAttendance,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              icon: _isMarking
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_rounded),
              label: Text(
                _hasMarkedToday
                    ? 'Attendance Marked'
                    : _isMarking
                    ? 'Saving...'
                    : 'Mark Today',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid() {
    final stats = [
      _AttendanceStat(
        'Current Streak',
        _isLoading ? '...' : '$_currentStreak days',
        Icons.local_fire_department_rounded,
        const Color(0xFFF97316),
      ),
      _AttendanceStat(
        'This Month',
        _isLoading ? '...' : '$_monthlyAttendance',
        Icons.calendar_month_rounded,
        const Color(0xFF2563EB),
      ),
      _AttendanceStat(
        '30-Day Rate',
        _isLoading ? '...' : '${_attendancePercentage.toStringAsFixed(0)}%',
        Icons.insights_rounded,
        const Color(0xFF0F766E),
      ),
      _AttendanceStat(
        'Total Records',
        _isLoading ? '...' : '${_attendanceHistory.length}',
        Icons.fact_check_rounded,
        const Color(0xFF7C3AED),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: stats.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        mainAxisExtent: 126,
      ),
      itemBuilder: (context, index) {
        final stat = stats[index];
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: stat.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(stat.icon, color: stat.color, size: 18),
              ),
              const Spacer(),
              Text(
                stat.label,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                stat.value,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCalendarCard() {
    final firstDay = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final leadingEmpty = firstDay.weekday - 1;
    final daysInMonth = _daysInMonth(_visibleMonth);
    final totalSlots = leadingEmpty + daysInMonth;
    final trailingEmpty = (7 - (totalSlots % 7)) % 7;
    final cellCount = totalSlots + trailingEmpty;
    final selectedDate = _selectedDate;
    final selectedRecord = selectedDate == null ? null : _recordForDate(selectedDate);
    final selectedIsFuture = selectedDate != null && _isFutureDate(selectedDate);

    const weekDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Monthly Calendar',
                      style: TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Tap any date to check its attendance status.',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _changeMonth(-1),
                icon: const Icon(Icons.chevron_left_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFF8FAFC),
                  minimumSize: const Size(36, 36),
                  padding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _monthLabel(_visibleMonth),
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                onPressed: () => _changeMonth(1),
                icon: const Icon(Icons.chevron_right_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFF8FAFC),
                  minimumSize: const Size(36, 36),
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: weekDays
                .map(
                  (day) => Expanded(
                    child: Center(
                      child: Text(
                        day,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: cellCount,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              mainAxisExtent: 36,
            ),
            itemBuilder: (context, index) {
              if (index < leadingEmpty || index >= leadingEmpty + daysInMonth) {
                return const SizedBox.shrink();
              }

              final dayNumber = index - leadingEmpty + 1;
              final date = DateTime(_visibleMonth.year, _visibleMonth.month, dayNumber);
              final record = _recordForDate(date);
              final isFuture = _isFutureDate(date);
              final isSelected = selectedDate != null && _isSameDate(selectedDate, date);

              final backgroundColor = record != null
                  ? const Color(0xFFDCFCE7)
                  : isFuture
                  ? const Color(0xFFF8FAFC)
                  : const Color(0xFFFEE2E2);
              final textColor = record != null
                  ? const Color(0xFF166534)
                  : isFuture
                  ? const Color(0xFF94A3B8)
                  : const Color(0xFFB91C1C);
              final borderColor = isSelected
                  ? const Color(0xFF2563EB)
                  : record != null
                  ? const Color(0xFF86EFAC)
                  : isFuture
                  ? const Color(0xFFE2E8F0)
                  : const Color(0xFFFCA5A5);

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _selectDate(date),
                  borderRadius: BorderRadius.circular(14),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: borderColor,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Text(
                      '$dayNumber',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: const [
              _CalendarLegendChip(
                label: 'Present',
                backgroundColor: Color(0xFFDCFCE7),
                borderColor: Color(0xFF86EFAC),
                textColor: Color(0xFF166534),
              ),
              _CalendarLegendChip(
                label: 'Absent',
                backgroundColor: Color(0xFFFEE2E2),
                borderColor: Color(0xFFFCA5A5),
                textColor: Color(0xFFB91C1C),
              ),
              _CalendarLegendChip(
                label: 'Future',
                backgroundColor: Color(0xFFF8FAFC),
                borderColor: Color(0xFFE2E8F0),
                textColor: Color(0xFF64748B),
              ),
            ],
          ),
          if (selectedDate != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatDate(_dateKeyFromDate(selectedDate)),
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    selectedRecord != null
                        ? 'Attendance marked${(selectedRecord['time']?.toString().isNotEmpty ?? false) ? ' at ${selectedRecord['time']}' : ''}.'
                        : selectedIsFuture
                        ? 'This date is in the future, so attendance is not expected yet.'
                        : 'Attendance was not marked on this date.',
                    style: TextStyle(
                      color: selectedRecord != null
                          ? const Color(0xFF166534)
                          : selectedIsFuture
                          ? const Color(0xFF64748B)
                          : const Color(0xFFB91C1C),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHistoryCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Attendance History',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_attendanceHistory.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'No attendance records yet. Mark today to create your first entry.',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            ..._attendanceHistory.map((record) {
              final rawDate = record['date']?.toString() ?? '';
              final time = record['time']?.toString() ?? '';
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
                        color: const Color(0xFF4F46E5).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.calendar_today_rounded,
                        color: Color(0xFF4F46E5),
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatDate(rawDate),
                            style: const TextStyle(
                              color: Color(0xFF0F172A),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            time.isEmpty ? 'Time unavailable' : 'Marked at $time',
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _AttendanceStat {
  const _AttendanceStat(this.label, this.value, this.icon, this.color);

  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _CalendarLegendChip extends StatelessWidget {
  const _CalendarLegendChip({
    required this.label,
    required this.backgroundColor,
    required this.borderColor,
    required this.textColor,
  });

  final String label;
  final Color backgroundColor;
  final Color borderColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
