import 'package:flutter/material.dart';

import '../../services/prediction_service.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final PredictionService _service = PredictionService();

  Map<String, dynamic>? _wasteData;
  Map<String, dynamic>? _studentData;
  bool _loading = true;
  String? _errorMessage;
  bool _wasteLoadFailed = false;
  bool _studentLoadFailed = false;

  @override
  void initState() {
    super.initState();
    _fetchAnalytics();
  }

  int _readInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  String _primaryFoodName() {
    final data = _studentData?['most_ordered_food'];
    if (data is Map && data['name'] != null) {
      return data['name'].toString();
    }
    final popularity = _studentData?['most_popular_food'];
    if (popularity is Map && popularity.isNotEmpty) {
      return popularity.keys.first.toString();
    }
    return 'No live orders yet';
  }

  Future<void> _fetchAnalytics() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
      _wasteLoadFailed = false;
      _studentLoadFailed = false;
    });

    try {
      Future<Map<String, dynamic>?> safeWaste() async {
        try {
          return await _service.getWasteReport();
        } catch (_) {
          _wasteLoadFailed = true;
          return null;
        }
      }

      Future<Map<String, dynamic>?> safeStudent() async {
        try {
          return await _service.getStudentAnalytics();
        } catch (_) {
          _studentLoadFailed = true;
          return null;
        }
      }

      final results = await Future.wait<Map<String, dynamic>?>([
        safeWaste(),
        safeStudent(),
      ]);
      final wasteResult = results[0];
      final studentResult = results[1];
      if (!mounted) return;
      setState(() {
        _wasteData = wasteResult ?? <String, dynamic>{};
        _studentData = studentResult ?? <String, dynamic>{};
        if (_wasteLoadFailed && _studentLoadFailed) {
          _errorMessage =
              'Faculty analytics is taking longer than expected right now. Pull to refresh in a moment.';
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

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 960;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: const Text('Faculty Analytics'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _fetchAnalytics,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? _buildErrorState()
          : RefreshIndicator(
              onRefresh: _fetchAnalytics,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                children: [
                  if (_wasteLoadFailed || _studentLoadFailed) ...[
                    _buildInfoBanner(
                      'Some analytics cards are still waiting on live data, so this screen is showing what was available first.',
                    ),
                    const SizedBox(height: 14),
                  ],
                  _buildHeroCard(),
                  const SizedBox(height: 18),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: width < 600 ? 1 : (isWide ? 4 : 2),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.25,
                    children: [
                      _metricTile(
                        'Total Orders',
                        '${_readInt(_studentData?['total_orders'])}',
                        Icons.receipt_long_rounded,
                        const Color(0xFF2563EB),
                      ),
                      _metricTile(
                        'Peak Time',
                        _studentData?['peak_order_time']?.toString() ?? 'N/A',
                        Icons.schedule_rounded,
                        const Color(0xFF0F766E),
                      ),
                      _metricTile(
                        'Waste %',
                        _wasteData?['Waste Percentage']?.toString() ?? '0%',
                        Icons.delete_outline_rounded,
                        const Color(0xFFF97316),
                      ),
                      _metricTile(
                        'Prepared',
                        '${_readInt(_wasteData?['Total Prepared'])}',
                        Icons.inventory_2_outlined,
                        const Color(0xFF7C3AED),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (isWide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildStudentBehaviorCard()),
                        const SizedBox(width: 16),
                        Expanded(child: _buildWasteCard()),
                      ],
                    )
                  else ...[
                    _buildStudentBehaviorCard(),
                    const SizedBox(height: 16),
                    _buildWasteCard(),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildErrorState() {
    return RefreshIndicator(
      onRefresh: _fetchAnalytics,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
        children: [
          _buildInfoBanner(_errorMessage!),
          const SizedBox(height: 18),
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
    return Container(
      padding: const EdgeInsets.all(24),
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
              _pill('Live order behavior', Icons.people_alt_rounded),
              _pill('Waste and sell-through', Icons.insights_rounded),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Faculty can see the same live campus food signals without digging through admin-only controls.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _studentData?['note']?.toString() ??
                _wasteData?['Note']?.toString() ??
                'This view combines current student ordering patterns with canteen waste outcomes.',
            style: const TextStyle(
              color: Color(0xFFE0F2FE),
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
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

  Widget _metricTile(String title, String value, IconData icon, Color color) {
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
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentBehaviorCard() {
    final topStudents =
        (_studentData?['top_students_list'] as List<dynamic>? ?? const [])
            .cast<Map>();

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
            'Student Behavior',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 14),
          _insightRow('Most ordered food', _primaryFoodName()),
          _insightRow(
            'Veg preference',
            _studentData?['veg_preference']?.toString() ?? '0%',
          ),
          _insightRow(
            'Peak order time',
            _studentData?['peak_order_time']?.toString() ?? 'N/A',
          ),
          const SizedBox(height: 16),
          const Text(
            'Top users by order count',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          if (topStudents.isEmpty)
            const Text(
              'No live student ranking is available yet.',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            )
          else
            ...topStudents.take(4).map((entry) {
              final name = entry['name']?.toString() ?? 'Campus user';
              final count = _readInt(entry['orders']);
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 220;
                    return compact
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.person_outline_rounded,
                                    color: Color(0xFF2563EB),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFF0F172A),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '$count orders',
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              const Icon(
                                Icons.person_outline_rounded,
                                color: Color(0xFF2563EB),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF0F172A),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  '$count orders',
                                  textAlign: TextAlign.right,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          );
                  },
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildWasteCard() {
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
            'Waste Snapshot',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 14),
          _insightRow(
            'Total prepared',
            '${_readInt(_wasteData?['Total Prepared'])}',
          ),
          _insightRow('Total sold', '${_readInt(_wasteData?['Total Sold'])}'),
          _insightRow(
            'Total wasted',
            '${_readInt(_wasteData?['Total Wasted'])}',
          ),
          _insightRow(
            'Sell-through',
            _wasteData?['Sell Through Percentage']?.toString() ?? '0%',
          ),
          _insightRow(
            'Estimated ML reduction',
            '${_readInt(_wasteData?['Estimated ML Waste Reduction'])} meals',
          ),
        ],
      ),
    );
  }

  Widget _insightRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 220;
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
