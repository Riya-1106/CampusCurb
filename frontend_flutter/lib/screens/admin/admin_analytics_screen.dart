import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../services/prediction_service.dart';

class _TrendLinePainter extends CustomPainter {
  final List<double> points;
  final Color color;

  _TrendLinePainter({required this.points, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final axis = Paint()
      ..color = Colors.black12
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(0, size.height - 1),
      Offset(size.width, size.height - 1),
      axis,
    );

    final maxValue = points.reduce(math.max).clamp(1.0, 100.0);
    final minValue = points.reduce(math.min).clamp(0.0, 100.0);
    final spread = (maxValue - minValue).abs() < 0.001
        ? 1.0
        : (maxValue - minValue);

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = points.length == 1
          ? size.width / 2
          : (i / (points.length - 1)) * size.width;
      final normalized = (points[i] - minValue) / spread;
      final y = size.height - (normalized * (size.height - 6)) - 3;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 2.5, Paint()..color = color);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TrendLinePainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.color != color;
  }
}

class AdminAnalyticsScreen extends StatefulWidget {
  const AdminAnalyticsScreen({super.key});

  @override
  State<AdminAnalyticsScreen> createState() => _AdminAnalyticsScreenState();
}

class _AdminAnalyticsScreenState extends State<AdminAnalyticsScreen> {
  final PredictionService _service = PredictionService();
  Map<String, dynamic>? studentData;
  Map<String, dynamic>? predictionData;
  Map<String, dynamic>? mlOverviewData;
  Map<String, dynamic>? trainingStatusData;
  bool loading = true;
  bool retraining = false;
  bool partialDataUnavailable = false;

  @override
  void initState() {
    super.initState();
    fetchAnalytics();
  }

  Future<void> fetchAnalytics() async {
    setState(() {
      loading = true;
    });

    Future<Map<String, dynamic>?> safeLoad(
      Future<Map<String, dynamic>> request,
    ) async {
      try {
        return await request;
      } catch (_) {
        return null;
      }
    }

    final results = await Future.wait<Map<String, dynamic>?>(
      [
        safeLoad(_service.getStudentAnalytics()),
        safeLoad(_service.getPredictionAccuracy()),
        safeLoad(_service.getMlOverview()),
      ],
    );

    if (!mounted) return;
    setState(() {
      studentData = results[0];
      predictionData = results[1];
      mlOverviewData = results[2];
      trainingStatusData = Map<String, dynamic>.from(
        results[2]?['training_status'] as Map<String, dynamic>? ?? {},
      );
      partialDataUnavailable = results.any((result) => result == null);
      loading = false;
    });
  }

  Future<void> refreshTrainingStatus() async {
    try {
      final status = await _service.getMlTrainingStatus();
      if (!mounted) return;
      setState(() {
        trainingStatusData = status;
      });
    } catch (_) {
      // Keep the last known training status on screen.
    }
  }

  Widget dataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(value),
        ],
      ),
    );
  }

  Widget sectionCard({required String title, required Widget child}) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget chipStat(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }

  Color _statusColor(String label) {
    final normalized = label.trim().toLowerCase();
    if (normalized.contains('running') || normalized.contains('progress')) {
      return const Color(0xFF2563EB);
    }
    if (normalized.contains('strong') ||
        normalized.contains('reliable') ||
        normalized.contains('healthy') ||
        normalized.contains('success')) {
      return const Color(0xFF15803D);
    }
    if (normalized.contains('promising') ||
        normalized.contains('improving')) {
      return const Color(0xFF2563EB);
    }
    if (normalized.contains('early') ||
        normalized.contains('needs') ||
        normalized.contains('failed')) {
      return const Color(0xFFB45309);
    }
    return const Color(0xFF64748B);
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

  String _formatDuration(dynamic value) {
    final seconds = _toDouble(value);
    if (seconds <= 0) return 'Not recorded';
    if (seconds < 60) return '${seconds.toStringAsFixed(seconds < 10 ? 1 : 0)} sec';
    final minutes = (seconds / 60).floor();
    final remaining = (seconds % 60).round();
    return '$minutes min ${remaining}s';
  }

  String _humanizeError(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '').trim();
    if (text.isEmpty) {
      return 'Training could not be completed right now.';
    }
    return text;
  }

  Future<void> triggerRetraining() async {
    if (retraining) return;
    setState(() {
      retraining = true;
    });

    try {
      final response = await _service.retrainModel();
      if (!mounted) return;
      await fetchAnalytics();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            response['message']?.toString() ?? 'Model retrained successfully.',
          ),
        ),
      );
    } catch (error) {
      await refreshTrainingStatus();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_humanizeError(error)),
          backgroundColor: const Color(0xFFB91C1C),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          retraining = false;
        });
      }
    }
  }

  Widget statusPill(String label) {
    final color = _statusColor(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget simpleList<T>({
    required List<T> items,
    required Widget Function(T item, int index) builder,
    required String emptyText,
  }) {
    if (items.isEmpty) {
      return Text(emptyText, style: const TextStyle(color: Colors.black54));
    }

    return Column(
      children: List.generate(
        items.length,
        (index) => builder(items[index], index),
      ),
    );
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  Widget barChartList({
    required List<Map<String, dynamic>> data,
    required String title,
    required String labelKey,
    required String valueKey,
    required Color color,
    String emptyText = 'No chart data available.',
  }) {
    if (data.isEmpty) {
      return Text(emptyText, style: const TextStyle(color: Colors.black54));
    }

    final maxValue = data
        .map((e) => _toDouble(e[valueKey]))
        .fold<double>(0, math.max)
        .clamp(1, double.infinity);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        ...data.map((item) {
          final label = item[labelKey]?.toString() ?? 'N/A';
          final value = _toDouble(item[valueKey]);
          final factor = (value / maxValue).clamp(0.0, 1.0);

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(label, overflow: TextOverflow.ellipsis),
                    ),
                    Text(value.toStringAsFixed(value % 1 == 0 ? 0 : 1)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    minHeight: 10,
                    value: factor,
                    color: color,
                    backgroundColor: color.withValues(alpha: 0.15),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget ratioChart(Map<String, dynamic> vegRatio) {
    final veg = _toDouble(vegRatio['veg_percentage']).clamp(0, 100);
    final nonVeg = _toDouble(vegRatio['non_veg_percentage']).clamp(0, 100);
    final sum = (veg + nonVeg) == 0 ? 1.0 : veg + nonVeg;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Veg vs Non-Veg Split',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 16,
            child: Row(
              children: [
                Expanded(
                  flex: ((veg / sum) * 1000).round(),
                  child: Container(color: const Color(0xFF2E9F65)),
                ),
                Expanded(
                  flex: ((nonVeg / sum) * 1000).round(),
                  child: Container(color: const Color(0xFFB5482A)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Veg: ${veg.toStringAsFixed(1)}% • Non-Veg: ${nonVeg.toStringAsFixed(1)}%',
        ),
      ],
    );
  }

  Widget accuracyTrendChart(List<Map<String, dynamic>> logs) {
    final points = logs
        .map((e) => _toDouble(e['accuracy_percentage']))
        .where((v) => v >= 0)
        .toList();

    if (points.isEmpty) {
      return const Text(
        'No trend data available.',
        style: TextStyle(color: Colors.black54),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Prediction Accuracy Trend',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 90,
          width: double.infinity,
          child: CustomPaint(
            painter: _TrendLinePainter(
              points: points.reversed.toList(),
              color: const Color(0xFF2E6FD8),
            ),
          ),
        ),
      ],
    );
  }

  Widget comparisonTrendChart({
    required String title,
    required List<Map<String, dynamic>> data,
    required String labelKey,
    required String primaryKey,
    required String secondaryKey,
    required String primaryLabel,
    required String secondaryLabel,
    required Color primaryColor,
    required Color secondaryColor,
    String emptyText = 'No trend data available.',
  }) {
    if (data.isEmpty) {
      return Text(emptyText, style: const TextStyle(color: Colors.black54));
    }

    final maxValue = data
        .expand(
          (item) => [
            _toDouble(item[primaryKey]),
            _toDouble(item[secondaryKey]),
          ],
        )
        .fold<double>(0, math.max)
        .clamp(1, double.infinity);

    Widget metricRow(String label, double value, Color color) {
      return Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                minHeight: 10,
                value: (value / maxValue).clamp(0.0, 1.0),
                color: color,
                backgroundColor: color.withValues(alpha: 0.15),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 42,
            child: Text(
              value.toStringAsFixed(value % 1 == 0 ? 0 : 1),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        ...data.map((item) {
          final label = item[labelKey]?.toString() ?? 'N/A';
          final primaryValue = _toDouble(item[primaryKey]);
          final secondaryValue = _toDouble(item[secondaryKey]);
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 10),
                metricRow(primaryLabel, primaryValue, primaryColor),
                const SizedBox(height: 8),
                metricRow(secondaryLabel, secondaryValue, secondaryColor),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget singleSeriesTrendChart({
    required String title,
    required List<Map<String, dynamic>> data,
    required String labelKey,
    required String valueKey,
    required Color color,
    String suffix = '',
    String emptyText = 'No trend data available.',
  }) {
    final points = data.map((item) => _toDouble(item[valueKey])).toList();
    if (points.isEmpty) {
      return Text(emptyText, style: const TextStyle(color: Colors.black54));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        SizedBox(
          height: 90,
          width: double.infinity,
          child: CustomPaint(
            painter: _TrendLinePainter(
              points: points,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: data.map((item) {
            final label = item[labelKey]?.toString() ?? 'N/A';
            final value = _toDouble(item[valueKey]);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: color.withValues(alpha: 0.20)),
              ),
              child: Text(
                '$label • ${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)}$suffix',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final analytics = studentData;
    final accuracy = predictionData;
    final foodRankings = List<Map<String, dynamic>>.from(
      (analytics?['food_rankings'] as List<dynamic>? ?? []).map(
        (e) => Map<String, dynamic>.from(e as Map),
      ),
    );
    final topStudents = List<Map<String, dynamic>>.from(
      (analytics?['top_students_list'] as List<dynamic>? ?? []).map(
        (e) => Map<String, dynamic>.from(e as Map),
      ),
    );
    final recentLogs = List<Map<String, dynamic>>.from(
      (accuracy?['recent_logs'] as List<dynamic>? ?? []).map(
        (e) => Map<String, dynamic>.from(e as Map),
      ),
    );
    final accuracyByFood = List<Map<String, dynamic>>.from(
      (accuracy?['accuracy_by_food'] as List<dynamic>? ?? []).map(
        (e) => Map<String, dynamic>.from(e as Map),
      ),
    );
    final mostOrdered = Map<String, dynamic>.from(
      analytics?['most_ordered_food'] as Map<String, dynamic>? ?? {},
    );
    final peakDetails = Map<String, dynamic>.from(
      analytics?['peak_order_time_details'] as Map<String, dynamic>? ?? {},
    );
    final vegRatio = Map<String, dynamic>.from(
      analytics?['veg_vs_non_veg_ratio'] as Map<String, dynamic>? ?? {},
    );
    final mlOverview = mlOverviewData;
    final training = Map<String, dynamic>.from(
      mlOverview?['training'] as Map<String, dynamic>? ?? {},
    );
    final trainingStatus = Map<String, dynamic>.from(
      trainingStatusData ??
          mlOverview?['training_status'] as Map<String, dynamic>? ??
          {},
    );
    final demandSummary = Map<String, dynamic>.from(
      mlOverview?['demand_summary'] as Map<String, dynamic>? ?? {},
    );
    final mlAccuracySummary = Map<String, dynamic>.from(
      mlOverview?['accuracy_summary'] as Map<String, dynamic>? ?? {},
    );
    final impactSummary = Map<String, dynamic>.from(
      mlOverview?['impact_summary'] as Map<String, dynamic>? ?? {},
    );
    final confidenceBreakdown = Map<String, dynamic>.from(
      mlOverview?['confidence_breakdown'] as Map<String, dynamic>? ?? {},
    );
    final topRecommendations = List<Map<String, dynamic>>.from(
      (mlOverview?['top_recommendations'] as List<dynamic>? ?? []).map(
        (e) => Map<String, dynamic>.from(e as Map),
      ),
    );
    final lowConfidenceItems = List<Map<String, dynamic>>.from(
      (mlOverview?['low_confidence_items'] as List<dynamic>? ?? []).map(
        (e) => Map<String, dynamic>.from(e as Map),
      ),
    );
    final operatorActions = List<String>.from(
      (mlOverview?['operator_actions'] as List<dynamic>? ?? []).map(
        (e) => e.toString(),
      ),
    );
    final trendData = Map<String, dynamic>.from(
      mlOverview?['trends'] as Map<String, dynamic>? ?? {},
    );
    final predictedVsActualTrend = List<Map<String, dynamic>>.from(
      (trendData['predicted_vs_actual'] as List<dynamic>? ?? []).map(
        (e) => Map<String, dynamic>.from(e as Map),
      ),
    );
    final wasteReductionTrend = List<Map<String, dynamic>>.from(
      (trendData['waste_reduction'] as List<dynamic>? ?? []).map(
        (e) => Map<String, dynamic>.from(e as Map),
      ),
    );
    final confidenceTrend = List<Map<String, dynamic>>.from(
      (trendData['confidence'] as List<dynamic>? ?? []).map(
        (e) => Map<String, dynamic>.from(e as Map),
      ),
    );
    final recentTrainingRuns = List<Map<String, dynamic>>.from(
      (trainingStatus['recent_runs'] as List<dynamic>? ?? []).map(
        (e) => Map<String, dynamic>.from(e as Map),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('System Analytics')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : analytics == null && accuracy == null && mlOverview == null
          ? const Center(child: Text('No analytics data available.'))
          : RefreshIndicator(
              onRefresh: fetchAnalytics,
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  if (partialDataUnavailable) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: Color(0xFFB45309),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Some analytics sections could not be loaded right now, but the ML overview and training controls are still available.',
                              style: TextStyle(
                                color: Color(0xFF92400E),
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  sectionCard(
                    title: 'ML Impact Snapshot',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          impactSummary['headline']?.toString() ??
                              'The admin view will show clearer ML impact once live forecasting, actuals, and waste logs build up.',
                          style: const TextStyle(
                            color: Color(0xFF334155),
                            fontWeight: FontWeight.w600,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            statusPill(
                              impactSummary['model_health']?.toString() ??
                                  'Not trained',
                            ),
                            statusPill(
                              impactSummary['data_readiness']?.toString() ??
                                  'Needs more live canteen logs',
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            chipStat(
                              'Waste Saved vs Baseline',
                              '${impactSummary['waste_saved_units'] ?? 0}',
                              const Color(0xFF15803D),
                            ),
                            chipStat(
                              'Waste Reduction',
                              '${impactSummary['waste_reduction_percentage'] ?? 0}%',
                              const Color(0xFF0F7A8B),
                            ),
                            chipStat(
                              'Resolved Predictions',
                              '${mlAccuracySummary['resolved_predictions'] ?? 0}/${mlAccuracySummary['total_predictions'] ?? 0}',
                              const Color(0xFF2E6FD8),
                            ),
                            chipStat(
                              'Forecast Coverage',
                              '${impactSummary['forecast_coverage_percentage'] ?? 0}%',
                              const Color(0xFF7C3AED),
                            ),
                            chipStat(
                              'Overall Accuracy',
                              '${mlAccuracySummary['overall_accuracy_percentage'] ?? 0}%',
                              const Color(0xFF2E9F65),
                            ),
                            chipStat(
                              'Low-Confidence Share',
                              '${impactSummary['low_confidence_rate'] ?? 0}%',
                              const Color(0xFFB5482A),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        dataRow(
                          'Baseline Waste',
                          '${impactSummary['baseline_waste'] ?? 0}',
                        ),
                        dataRow(
                          'Waste After ML',
                          '${impactSummary['waste_after_ml'] ?? 0}',
                        ),
                        dataRow(
                          'Prediction Logs Used in Waste Analysis',
                          '${impactSummary['prediction_count_used'] ?? 0}',
                        ),
                        dataRow(
                          'Pending Actuals',
                          '${mlAccuracySummary['pending_predictions'] ?? 0}',
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'What Admin Should Do Next',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        simpleList<String>(
                          items: operatorActions,
                          emptyText: 'No operator guidance is available yet.',
                          builder: (item, index) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 24,
                                  height: 24,
                                  alignment: Alignment.center,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFE0F2FE),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    '${index + 1}',
                                    style: const TextStyle(
                                      color: Color(0xFF0F172A),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    item,
                                    style: const TextStyle(
                                      color: Color(0xFF334155),
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
                    ),
                  ),
                  const SizedBox(height: 12),
                  sectionCard(
                    title: 'ML Training Control',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          retraining
                              ? 'Retraining is running now. This uses the same shared pipeline that the weekly scheduler will trigger.'
                              : 'This shows the last shared training run. Manual retraining here updates the same model bundle used by forecasting and weekly refreshes.',
                          style: const TextStyle(
                            color: Color(0xFF334155),
                            fontWeight: FontWeight.w600,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            statusPill(
                              trainingStatus['status_label']?.toString() ??
                                  'Not started',
                            ),
                            chipStat(
                              'Best Model',
                              trainingStatus['best_model_name']?.toString() ??
                                  training['best_model_name']?.toString() ??
                                  'Not trained',
                              const Color(0xFF2E6FD8),
                            ),
                            chipStat(
                              'Dataset Rows',
                              '${trainingStatus['dataset_rows'] ?? training['dataset_rows'] ?? 0}',
                              const Color(0xFF0F7A8B),
                            ),
                            chipStat(
                              'Live Rows Added',
                              '${trainingStatus['live_rows_added'] ?? training['live_rows_added'] ?? 0}',
                              const Color(0xFF7C3AED),
                            ),
                            chipStat(
                              'Best R²',
                              '${trainingStatus['best_r2'] ?? training['best_r2'] ?? 0}',
                              const Color(0xFF15803D),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        dataRow(
                          'Last Completed',
                          _formatTimestamp(trainingStatus['last_completed_at']),
                        ),
                        dataRow(
                          'Last Started',
                          _formatTimestamp(trainingStatus['last_started_at']),
                        ),
                        dataRow(
                          'Trigger',
                          trainingStatus['last_trigger']?.toString() ??
                              'Not available yet',
                        ),
                        dataRow(
                          'Duration',
                          _formatDuration(
                            trainingStatus['last_duration_seconds'],
                          ),
                        ),
                        dataRow(
                          'Training Split',
                          '${trainingStatus['train_rows'] ?? training['train_rows'] ?? 0} train / ${trainingStatus['test_rows'] ?? training['test_rows'] ?? 0} test',
                        ),
                        if ((trainingStatus['last_error']?.toString() ?? '')
                            .isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFFECACA),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Last Failure',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFFB91C1C),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  trainingStatus['last_error']?.toString() ?? '',
                                  style: const TextStyle(
                                    color: Color(0xFF7F1D1D),
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            ElevatedButton.icon(
                              onPressed: retraining ? null : triggerRetraining,
                              icon: retraining
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.auto_graph_rounded),
                              label: Text(
                                retraining ? 'Retraining…' : 'Retrain Now',
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: retraining ? null : refreshTrainingStatus,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Refresh Status'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Recent Training Runs',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        simpleList<Map<String, dynamic>>(
                          items: recentTrainingRuns,
                          emptyText: 'No training history is available yet.',
                          builder: (item, index) => Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Text(
                                '${item['best_model_name'] ?? 'Model run'} • ${item['status'] ?? 'unknown'}',
                              ),
                              subtitle: Text(
                                'Trigger: ${item['trigger'] ?? 'manual'} • Completed: ${_formatTimestamp(item['completed_at'])}',
                              ),
                              trailing: Text(
                                item['status']?.toString() == 'failed'
                                    ? 'Issue'
                                    : '${item['best_r2'] ?? 0} R²',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  sectionCard(
                    title: 'ML System Overview',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            chipStat(
                              'Best Model',
                              '${training['best_model_name'] ?? 'Not trained'}',
                              const Color(0xFF2E6FD8),
                            ),
                            chipStat(
                              'Training Rows',
                              '${training['dataset_rows'] ?? 0}',
                              const Color(0xFF0F7A8B),
                            ),
                            chipStat(
                              'Best R²',
                              '${training['best_r2'] ?? 0}',
                              const Color(0xFF2E9F65),
                            ),
                            chipStat(
                              'Resolved Prediction Rate',
                              '${mlAccuracySummary['resolved_prediction_rate'] ?? 0}%',
                              const Color(0xFFB45309),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        dataRow(
                          'Forecasted Items',
                          '${demandSummary['items_forecasted'] ?? 0}',
                        ),
                        dataRow(
                          'Active Menu Items',
                          '${demandSummary['active_menu_items'] ?? 0}',
                        ),
                        dataRow(
                          'Predicted Demand Total',
                          '${demandSummary['total_predicted_demand'] ?? 0}',
                        ),
                        dataRow(
                          'Suggested Preparation Total',
                          '${demandSummary['total_suggested_preparation'] ?? 0}',
                        ),
                        dataRow(
                          'Average Confidence',
                          '${demandSummary['average_confidence'] ?? 0}%',
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Low Confidence Breakdown',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            chipStat(
                              'Limited History',
                              '${confidenceBreakdown['limited_history'] ?? 0}',
                              const Color(0xFFB5482A),
                            ),
                            chipStat(
                              'Weak Slot History',
                              '${confidenceBreakdown['weak_same_slot_history'] ?? 0}',
                              const Color(0xFFF97316),
                            ),
                            chipStat(
                              'Other',
                              '${confidenceBreakdown['other'] ?? 0}',
                              const Color(0xFF64748B),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Top Live Recommendations',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        simpleList<Map<String, dynamic>>(
                          items: topRecommendations,
                          emptyText: 'No live forecast recommendations available.',
                          builder: (item, index) => Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Text(item['food_item']?.toString() ?? 'Unknown'),
                              subtitle: Text(
                                'Predict ${item['predicted_demand'] ?? 0} • Prepare ${item['suggested_preparation'] ?? 0} • Waste ${item['expected_waste'] ?? 0}',
                              ),
                              trailing: Text(
                                item['confidence_label']?.toString() ?? 'Low',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Low Confidence Forecasts',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        simpleList<Map<String, dynamic>>(
                          items: lowConfidenceItems,
                          emptyText: 'No low-confidence forecast items right now.',
                          builder: (item, index) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.warning_amber_rounded),
                            title: Text(item['food_item']?.toString() ?? 'Unknown'),
                            subtitle: Text(
                              item['recommended_action']?.toString() ??
                                  'Review recent demand before preparing.',
                            ),
                            trailing: Text(
                              '${item['confidence_score'] ?? 0}%',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  sectionCard(
                    title: 'Operational Trend Charts',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        comparisonTrendChart(
                          title: 'Predicted vs Actual Sales',
                          data: predictedVsActualTrend,
                          labelKey: 'label',
                          primaryKey: 'predicted_total',
                          secondaryKey: 'actual_total',
                          primaryLabel: 'Predicted',
                          secondaryLabel: 'Actual',
                          primaryColor: const Color(0xFF2E6FD8),
                          secondaryColor: const Color(0xFF15803D),
                          emptyText:
                              'Predicted vs actual trend will appear after more resolved prediction logs are available.',
                        ),
                        const SizedBox(height: 18),
                        comparisonTrendChart(
                          title: 'Waste Reduction Over Time',
                          data: wasteReductionTrend,
                          labelKey: 'label',
                          primaryKey: 'baseline_waste',
                          secondaryKey: 'actual_waste',
                          primaryLabel: 'Baseline',
                          secondaryLabel: 'Actual',
                          primaryColor: const Color(0xFFB5482A),
                          secondaryColor: const Color(0xFF0F7A8B),
                          emptyText:
                              'Waste reduction trend will appear after canteen operations are matched with prediction logs.',
                        ),
                        const SizedBox(height: 18),
                        singleSeriesTrendChart(
                          title: 'Confidence Trend Over Time',
                          data: confidenceTrend,
                          labelKey: 'label',
                          valueKey: 'average_confidence',
                          color: const Color(0xFF7C3AED),
                          suffix: '%',
                          emptyText:
                              'Confidence trend will appear after multiple forecast runs are logged.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  sectionCard(
                    title: 'Student Behavior Analytics',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            chipStat(
                              'Most Ordered Food',
                              '${mostOrdered['name'] ?? 'N/A'} (${mostOrdered['orders'] ?? 0})',
                              const Color(0xFF2E6FD8),
                            ),
                            chipStat(
                              'Peak Ordering Time',
                              '${peakDetails['slot'] ?? analytics?['peak_order_time'] ?? 'N/A'}',
                              const Color(0xFF0F7A8B),
                            ),
                            chipStat(
                              'Veg vs Non-Veg',
                              '${vegRatio['display'] ?? analytics?['veg_preference'] ?? 'N/A'}',
                              const Color(0xFF2E9F65),
                            ),
                            chipStat(
                              'Total Orders',
                              '${analytics?['total_orders'] ?? 0}',
                              const Color(0xFFB5482A),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        dataRow(
                          'Peak Slot Orders',
                          '${peakDetails['orders'] ?? 0}',
                        ),
                        dataRow('Veg Orders', '${vegRatio['veg_count'] ?? 0}'),
                        dataRow(
                          'Non-Veg Orders',
                          '${vegRatio['non_veg_count'] ?? 0}',
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Most Ordered Food Ranking',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        simpleList<Map<String, dynamic>>(
                          items: foodRankings,
                          emptyText: 'No food ranking data available.',
                          builder: (item, index) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 14,
                              child: Text('${index + 1}'),
                            ),
                            title: Text(item['name']?.toString() ?? 'Unknown'),
                            trailing: Text('${item['count'] ?? 0} orders'),
                          ),
                        ),
                        const SizedBox(height: 14),
                        barChartList(
                          data: foodRankings,
                          title: 'Food Orders Bar Chart',
                          labelKey: 'name',
                          valueKey: 'count',
                          color: const Color(0xFF2E6FD8),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Top Students',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        simpleList<Map<String, dynamic>>(
                          items: topStudents,
                          emptyText: 'No student order ranking available.',
                          builder: (item, index) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.person_outline),
                            title: Text(
                              item['student']?.toString() ?? 'Unknown student',
                            ),
                            trailing: Text('${item['orders'] ?? 0} orders'),
                          ),
                        ),
                        const SizedBox(height: 14),
                        barChartList(
                          data: topStudents,
                          title: 'Top Students Bar Chart',
                          labelKey: 'student',
                          valueKey: 'orders',
                          color: const Color(0xFF0F7A8B),
                          emptyText: 'No top-student chart data available.',
                        ),
                        const SizedBox(height: 16),
                        ratioChart(vegRatio),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  sectionCard(
                    title: 'Prediction Accuracy',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            chipStat(
                              'Overall Accuracy',
                              '${accuracy?['overall_accuracy_percentage'] ?? 0}%',
                              const Color(0xFF2E6FD8),
                            ),
                            chipStat(
                              'Prediction Logs',
                              '${accuracy?['total_predictions'] ?? 0}',
                              const Color(0xFFB5482A),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Recent Prediction Logs',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        simpleList<Map<String, dynamic>>(
                          items: recentLogs,
                          emptyText: 'No prediction logs available.',
                          builder: (item, index) => Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Text(
                                item['food_item']?.toString() ?? 'Unknown',
                              ),
                              subtitle: Text(
                                'Predicted: ${item['predicted_demand'] ?? 0} • Actual: ${item['actual_sold'] ?? 0}',
                              ),
                              trailing: Text(
                                '${item['accuracy_percentage'] ?? 0}%',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        accuracyTrendChart(recentLogs),
                        const SizedBox(height: 16),
                        const Text(
                          'Accuracy By Food',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        simpleList<Map<String, dynamic>>(
                          items: accuracyByFood,
                          emptyText: 'No food-wise accuracy data available.',
                          builder: (item, index) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              item['food_item']?.toString() ?? 'Unknown',
                            ),
                            subtitle: Text(
                              'Predicted Avg: ${item['predicted_average'] ?? 0} • Actual Avg: ${item['actual_average'] ?? 0}',
                            ),
                            trailing: Text(
                              '${item['accuracy_percentage'] ?? 0}%',
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        barChartList(
                          data: accuracyByFood,
                          title: 'Food-wise Accuracy Chart',
                          labelKey: 'food_item',
                          valueKey: 'accuracy_percentage',
                          color: const Color(0xFF2E9F65),
                          emptyText:
                              'No food-wise accuracy chart data available.',
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: fetchAnalytics,
                          child: const Text('Refresh'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
