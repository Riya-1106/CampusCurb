import 'package:flutter/material.dart';

import '../../services/prediction_service.dart';

class PredictionScreen extends StatefulWidget {
  const PredictionScreen({super.key});

  @override
  State<PredictionScreen> createState() => _PredictionScreenState();
}

class _PredictionScreenState extends State<PredictionScreen> {
  final PredictionService _service = PredictionService();

  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
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

  Future<void> _loadDashboard() async {
    setState(() {
      _loading = true;
    });

    try {
      final result = await _service.getDemandDashboard();
      if (!mounted) return;
      setState(() {
        _data = result;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Color _confidenceColor(String label) {
    switch (label.toLowerCase()) {
      case 'high':
        return const Color(0xFF15803D);
      case 'medium':
        return const Color(0xFFB45309);
      default:
        return const Color(0xFFB91C1C);
    }
  }

  IconData _trendIcon(String direction) {
    switch (direction.toLowerCase()) {
      case 'up':
        return Icons.trending_up_rounded;
      case 'down':
        return Icons.trending_down_rounded;
      default:
        return Icons.trending_flat_rounded;
    }
  }

  Widget _summaryChip(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
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
          Text(
            value,
            style: TextStyle(
              color: color ?? const Color(0xFF0F172A),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForecastCard(Map<String, dynamic> item) {
    final confidenceLabel = item['confidence_label']?.toString() ?? 'Low';
    final confidenceColor = _confidenceColor(confidenceLabel);
    final trendDirection = item['trend_direction']?.toString() ?? 'stable';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  _trendIcon(trendDirection),
                  color: const Color(0xFF2563EB),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['food_item']?.toString() ?? 'Menu item',
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${item['food_category'] ?? 'General'} • ${item['time_slot'] ?? ''}',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: confidenceColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$confidenceLabel confidence',
                  style: TextStyle(
                    color: confidenceColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _summaryChip(
                'Predicted demand',
                '${_toInt(item['predicted_demand'])}',
                const Color(0xFF2563EB),
              ),
              _summaryChip(
                'Suggested prep',
                '${_toInt(item['suggested_preparation'])}',
                const Color(0xFF15803D),
              ),
              _summaryChip(
                'Recent avg sales',
                _toDouble(item['recent_average_sales']).toStringAsFixed(1),
                const Color(0xFF7C3AED),
              ),
              _summaryChip(
                'Expected waste',
                '${_toInt(item['expected_waste'])}',
                const Color(0xFFB45309),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _infoRow(
            'Confidence score',
            '${_toDouble(item['confidence_score']).toStringAsFixed(1)}%',
            color: confidenceColor,
          ),
          _infoRow(
            'Recommended buffer',
            '${_toDouble(item['recommended_buffer_percentage']).toStringAsFixed(1)}%',
          ),
          _infoRow(
            'Expected sell-through',
            '${_toDouble(item['expected_sell_through_percentage']).toStringAsFixed(1)}%',
          ),
          _infoRow(
            'Historical prep average',
            '${_toInt(item['historical_preparation_average'])}',
          ),
          _infoRow(
            'Weather context',
            '${item['weather_type'] ?? 'Sunny'} • ${_toInt(item['temperature'])}°C',
          ),
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
                const Text(
                  'Why the model suggests this',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item['trend_reason']?.toString() ?? 'Demand is stable.',
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item['confidence_reason']?.toString() ??
                      'Confidence is based on item history, slot support, and demand stability.',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item['recommended_action']?.toString() ??
                      'Keep preparation close to the recent average.',
                  style: const TextStyle(
                    color: Color(0xFF0F766E),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = Map<String, dynamic>.from(
      _data?['summary'] as Map<String, dynamic>? ?? {},
    );
    final model = Map<String, dynamic>.from(
      _data?['model'] as Map<String, dynamic>? ?? {},
    );
    final rows = List<Map<String, dynamic>>.from(
      (_data?['dashboard'] as List<dynamic>? ?? []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
    final menuBasis = Map<String, dynamic>.from(
      _data?['menu_basis'] as Map<String, dynamic>? ?? {},
    );
    final activeMenuItems = List<Map<String, dynamic>>.from(
      (menuBasis['items'] as List<dynamic>? ?? []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
    final activeMenuNames = activeMenuItems
        .map((item) => item['name']?.toString() ?? '')
        .where((name) => name.trim().isNotEmpty)
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        title: const Text('Demand Forecast Dashboard'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _loadDashboard,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _data == null
            ? const Center(child: Text('Failed to load demand forecast'))
            : RefreshIndicator(
                onRefresh: _loadDashboard,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
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
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${model['name'] ?? 'Model'} • ${summary['time_slot'] ?? 'Current slot'}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Use live demand forecasting to prepare smarter, reduce stockouts, and limit waste.',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _data?['formula']?.toString() ??
                                'Predicted demand + safety margin',
                            style: const TextStyle(
                              color: Color(0xFFE0F2FE),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (activeMenuNames.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Forecast basis: ${activeMenuNames.length} active menu items',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (activeMenuNames.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Active Menu Forecast Base',
                              style: TextStyle(
                                color: Color(0xFF0F172A),
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'These are the current menu items the forecasting engine is using.',
                              style: TextStyle(
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: activeMenuItems.map((item) {
                                final price = _toInt(item['price']);
                                final category =
                                    item['category']?.toString() ?? 'general';
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        item['name']?.toString() ?? 'Menu item',
                                        style: const TextStyle(
                                          color: Color(0xFF0F172A),
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${category.toUpperCase()} • Rs.$price',
                                        style: const TextStyle(
                                          color: Color(0xFF64748B),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    if (activeMenuNames.isNotEmpty) const SizedBox(height: 18),
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: MediaQuery.of(context).size.width > 900 ? 4 : 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.25,
                      children: [
                        _summaryChip(
                          'Items forecasted',
                          '${_toInt(summary['items_forecasted'])}',
                          const Color(0xFF2563EB),
                        ),
                        _summaryChip(
                          'Predicted total demand',
                          '${_toInt(summary['total_predicted_demand'])}',
                          const Color(0xFF0F766E),
                        ),
                        _summaryChip(
                          'Suggested total prep',
                          '${_toInt(summary['total_suggested_preparation'])}',
                          const Color(0xFF7C3AED),
                        ),
                        _summaryChip(
                          'Avg confidence',
                          '${_toDouble(summary['average_confidence']).toStringAsFixed(1)}%',
                          const Color(0xFFF97316),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if ((_data?['low_confidence_items'] as List<dynamic>? ?? const [])
                        .isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFFED7AA)),
                        ),
                        child: Text(
                          'Low-confidence items need operator review: ${(_data?['low_confidence_items'] as List<dynamic>).join(', ')}',
                          style: const TextStyle(
                            color: Color(0xFF9A3412),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    if ((_data?['low_confidence_items'] as List<dynamic>? ?? const [])
                        .isNotEmpty)
                      const SizedBox(height: 18),
                    ...rows.map(_buildForecastCard),
                  ],
                ),
              ),
      ),
    );
  }
}
