import 'package:flutter/material.dart';

import '../../services/prediction_service.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final PredictionService _service = PredictionService();

  Map<String, dynamic>? _studentData;
  Map<String, dynamic>? _wasteData;
  Map<String, dynamic>? _accuracyData;
  bool _loading = true;
  String? _errorMessage;
  bool _studentLoadFailed = false;
  bool _wasteLoadFailed = false;
  bool _accuracyLoadFailed = false;

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  int _readInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  double _readDouble(dynamic value, {double fallback = 0}) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  Future<void> _loadAnalytics() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
      _studentLoadFailed = false;
      _wasteLoadFailed = false;
      _accuracyLoadFailed = false;
    });

    try {
      Future<Map<String, dynamic>> safeStudent() async {
        try {
          return await _service.getStudentAnalytics();
        } catch (_) {
          _studentLoadFailed = true;
          return const {};
        }
      }

      Future<Map<String, dynamic>> safeWaste() async {
        try {
          return await _service.getWasteReport();
        } catch (_) {
          _wasteLoadFailed = true;
          return const {};
        }
      }

      Future<Map<String, dynamic>> safeAccuracy() async {
        try {
          return await _service.getPredictionAccuracy();
        } catch (_) {
          _accuracyLoadFailed = true;
          return const {};
        }
      }

      final results = await Future.wait<Map<String, dynamic>>([
        safeStudent(),
        safeWaste(),
        safeAccuracy(),
      ]);
      final student = results[0];
      final waste = results[1];
      final accuracy = results[2];
      final studentHasData = student.isNotEmpty;
      final wasteHasData = waste.isNotEmpty;
      final accuracyHasData = accuracy.isNotEmpty;
      if (!mounted) return;
      setState(() {
        _studentData = student;
        _wasteData = waste;
        _accuracyData = accuracy;
        _studentLoadFailed = _studentLoadFailed && !studentHasData;
        _wasteLoadFailed = _wasteLoadFailed && !wasteHasData;
        _accuracyLoadFailed = _accuracyLoadFailed && !accuracyHasData;
        if (_studentLoadFailed && _wasteLoadFailed && _accuracyLoadFailed) {
          _errorMessage =
              'Canteen analytics is taking longer than expected right now. Pull to refresh in a moment.';
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

  String _popularFood() {
    final mostOrdered = _studentData?['most_ordered_food'];
    if (mostOrdered is Map && mostOrdered['name'] != null) {
      return mostOrdered['name'].toString();
    }
    final popularity = _studentData?['most_popular_food'];
    if (popularity is Map && popularity.isNotEmpty) {
      return popularity.keys.first.toString();
    }
    return 'No live orders yet';
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
        title: const Text('Canteen Analytics'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadAnalytics,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? _buildErrorState()
          : RefreshIndicator(
              onRefresh: _loadAnalytics,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  if (_studentLoadFailed || _wasteLoadFailed || _accuracyLoadFailed) ...[
                    _buildInfoBanner(
                      'Some analytics cards are still waiting on live data, so this screen is showing what was available first.',
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
                    mainAxisExtent: width < 600 ? 92 : 112,
                    children: [
                      _metricTile(
                        'Forecast accuracy',
                        '${_readDouble(_accuracyData?['overall_accuracy_percentage']).toStringAsFixed(1)}%',
                        Icons.verified_rounded,
                        const Color(0xFF2563EB),
                      ),
                      _metricTile(
                        'Resolved predictions',
                        '${_readInt(_accuracyData?['resolved_predictions'])}',
                        Icons.fact_check_rounded,
                        const Color(0xFF0F766E),
                      ),
                      _metricTile(
                        'Waste percentage',
                        _wasteData?['Waste Percentage']?.toString() ?? '0%',
                        Icons.delete_outline_rounded,
                        const Color(0xFFF97316),
                      ),
                      _metricTile(
                        'Top ordered item',
                        _popularFood(),
                        Icons.local_fire_department_rounded,
                        const Color(0xFF7C3AED),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (isWide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildDemandCard()),
                        const SizedBox(width: 16),
                        Expanded(child: _buildAccuracyCard()),
                      ],
                    )
                  else ...[
                    _buildDemandCard(),
                    const SizedBox(height: 12),
                    _buildAccuracyCard(),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildErrorState() {
    return RefreshIndicator(
      onRefresh: _loadAnalytics,
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
    return Container(
      padding: const EdgeInsets.all(18),
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
              _pill('Live student demand', Icons.people_alt_rounded),
              _pill('Waste + accuracy', Icons.insights_rounded),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Watch ordering behavior, forecasting accuracy, and waste together so operations can react faster.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _wasteData?['Note']?.toString() ??
                'This view is built from current canteen outcomes plus live student activity.',
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
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

  Widget _metricTile(String title, String value, IconData icon, Color color) {
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
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 18),
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
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
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

  Widget _buildDemandCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Demand Signals',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 10),
          _infoRow('Most ordered food', _popularFood()),
          _infoRow(
            'Peak order time',
            _studentData?['peak_order_time']?.toString() ?? 'N/A',
          ),
          _infoRow(
            'Veg preference',
            _studentData?['veg_preference']?.toString() ?? '0%',
          ),
          _infoRow(
            'Total student orders',
            '${_readInt(_studentData?['total_orders'])}',
          ),
        ],
      ),
    );
  }

  Widget _buildAccuracyCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Operations Outcome',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 10),
          _infoRow(
            'Total prepared',
            '${_readInt(_wasteData?['Total Prepared'])}',
          ),
          _infoRow('Total sold', '${_readInt(_wasteData?['Total Sold'])}'),
          _infoRow('Total wasted', '${_readInt(_wasteData?['Total Wasted'])}'),
          _infoRow(
            'Estimated ML waste reduction',
            '${_readInt(_wasteData?['Estimated ML Waste Reduction'])} meals',
          ),
          _infoRow(
            'Prediction accuracy',
            '${_readDouble(_accuracyData?['overall_accuracy_percentage']).toStringAsFixed(1)}%',
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
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
      ),
    );
  }
}
