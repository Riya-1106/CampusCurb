import 'package:flutter/material.dart';

import '../../services/prediction_service.dart';

class AdminWasteMonitoringScreen extends StatefulWidget {
  const AdminWasteMonitoringScreen({super.key});

  @override
  State<AdminWasteMonitoringScreen> createState() =>
      _AdminWasteMonitoringScreenState();
}

class _AdminWasteMonitoringScreenState
    extends State<AdminWasteMonitoringScreen> {
  final PredictionService _service = PredictionService();
  Map<String, dynamic>? data;
  bool loading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    fetchWasteReport();
  }

  Future<void> fetchWasteReport() async {
    if (!mounted) return;
    setState(() {
      loading = data == null;
      errorMessage = null;
    });

    try {
      final result = await _service.getWasteReport();
      if (!mounted) return;
      setState(() {
        data = result;
        loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        errorMessage = error.toString().replaceFirst('Exception: ', '');
        loading = false;
      });
    }
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    final cleaned = value?.toString().replaceAll(RegExp(r'[^0-9.-]'), '') ?? '';
    return double.tryParse(cleaned)?.round() ?? 0;
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    final cleaned = value?.toString().replaceAll(RegExp(r'[^0-9.-]'), '') ?? '';
    return double.tryParse(cleaned) ?? 0;
  }

  String _value(String key, {String fallback = '0'}) {
    final raw = data?[key];
    if (raw == null || raw.toString().trim().isEmpty) return fallback;
    return raw.toString();
  }

  List<Map<String, dynamic>> _list(String key) {
    return List<Map<String, dynamic>>.from(
      (data?[key] as List<dynamic>? ?? []).whereType<Map>().map(
        (item) => Map<String, dynamic>.from(item),
      ),
    );
  }

  Widget _pill(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _metricCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required double width,
    String helper = '',
  }) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 14),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (helper.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                helper,
                style: const TextStyle(color: Color(0xFF64748B), height: 1.3),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required Widget child,
    IconData icon = Icons.analytics_outlined,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: const Color(0xFF2563EB)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _heroCard() {
    final saved = _toInt(data?['Estimated ML Waste Reduction']);
    final baseline = _toInt(data?['Waste Baseline']);
    final afterMl = _toInt(data?['Waste After ML']);
    final wasteRate = _value('Waste Percentage', fallback: '0%');
    final resolved = _toInt(data?['Resolved ML Predictions']);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: 0.18),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 720;
          final headline = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _pill(
                    'ML impact view',
                    Icons.auto_graph_rounded,
                    Colors.white,
                  ),
                  _pill('All logged data', Icons.history_rounded, Colors.white),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                '$saved meals saved from waste',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  height: 1.08,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Baseline waste $baseline portions reduced to $afterMl after ML-guided preparation.',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.45,
                ),
              ),
            ],
          );

          final sideStats = Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _heroStat('Current waste rate', wasteRate),
                const Divider(color: Colors.white24, height: 24),
                _heroStat(
                  'Sell-through',
                  _value('Sell Through Percentage', fallback: '0%'),
                ),
                const Divider(color: Colors.white24, height: 24),
                _heroStat('Resolved ML logs', '$resolved'),
              ],
            ),
          );

          if (!isWide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [headline, const SizedBox(height: 18), sideStats],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: headline),
              const SizedBox(width: 24),
              SizedBox(width: 300, child: sideStats),
            ],
          );
        },
      ),
    );
  }

  Widget _heroStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _impactComparison() {
    final baseline = _toDouble(data?['Waste Baseline']);
    final afterMl = _toDouble(data?['Waste After ML']);
    final saved = _toDouble(data?['Estimated ML Waste Reduction']);
    final maxValue = [
      baseline,
      afterMl,
      saved,
      1.0,
    ].reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'This compares old/historical preparation waste against the current ML-guided waste.',
          style: TextStyle(color: Color(0xFF64748B), height: 1.45),
        ),
        const SizedBox(height: 16),
        _barRow('Baseline waste', baseline, maxValue, const Color(0xFFDC2626)),
        const SizedBox(height: 12),
        _barRow('After ML', afterMl, maxValue, const Color(0xFF0F766E)),
        const SizedBox(height: 12),
        _barRow('Saved units', saved, maxValue, const Color(0xFF2563EB)),
      ],
    );
  }

  Widget _barRow(String label, double value, double maxValue, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF334155),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              value.toStringAsFixed(0),
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 12,
            value: (value / maxValue).clamp(0.0, 1.0),
            color: color,
            backgroundColor: color.withValues(alpha: 0.13),
          ),
        ),
      ],
    );
  }

  Widget _itemWasteList() {
    final items = _list('Item Waste Breakdown');
    if (items.isEmpty) {
      return const Text(
        'Item-wise waste will appear after the canteen records prepared and sold quantities.',
        style: TextStyle(color: Color(0xFF64748B), height: 1.45),
      );
    }

    final topItems = items.take(6).toList();
    final maxWaste = topItems
        .map((item) => _toDouble(item['wasted']))
        .fold<double>(1, (max, value) => value > max ? value : max);

    return Column(
      children: topItems.map((item) {
        final wasted = _toDouble(item['wasted']);
        final saved = _toInt(item['saved_units']);
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item['food_item']?.toString() ?? 'Unknown item',
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Text(
                    '${wasted.toStringAsFixed(0)} wasted',
                    style: const TextStyle(
                      color: Color(0xFFDC2626),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 9,
                  value: (wasted / maxWaste).clamp(0.0, 1.0),
                  color: const Color(0xFFDC2626),
                  backgroundColor: const Color(0xFFFEE2E2),
                ),
              ),
              const SizedBox(height: 9),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _miniTag(
                    'Prepared ${_toInt(item['prepared'])}',
                    const Color(0xFF2563EB),
                  ),
                  _miniTag(
                    'Sold ${_toInt(item['sold'])}',
                    const Color(0xFF16A34A),
                  ),
                  _miniTag('Saved $saved', const Color(0xFF0F766E)),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _miniTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _trendSection() {
    final trend = _list('Waste Reduction Trend');
    if (trend.isEmpty) {
      return const Text(
        'Waste trend will appear once prediction logs are matched with actual canteen operations across multiple days.',
        style: TextStyle(color: Color(0xFF64748B), height: 1.45),
      );
    }

    final maxValue = trend
        .expand(
          (item) => [
            _toDouble(item['baseline_waste']),
            _toDouble(item['actual_waste']),
          ],
        )
        .fold<double>(1, (max, value) => value > max ? value : max);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: trend.map((item) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item['label']?.toString() ??
                    item['target_date']?.toString() ??
                    'Date',
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              _smallBar(
                'Baseline',
                _toDouble(item['baseline_waste']),
                maxValue,
                const Color(0xFFDC2626),
              ),
              const SizedBox(height: 8),
              _smallBar(
                'Actual',
                _toDouble(item['actual_waste']),
                maxValue,
                const Color(0xFF0F766E),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _smallBar(String label, double value, double maxValue, Color color) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: (value / maxValue).clamp(0.0, 1.0),
              color: color,
              backgroundColor: color.withValues(alpha: 0.13),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 44,
          child: Text(
            value.toStringAsFixed(0),
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _adminActions() {
    final items = _list('Item Waste Breakdown');
    final worstItem = items.isNotEmpty
        ? items.first['food_item']?.toString() ?? 'highest-waste item'
        : 'highest-waste item';
    final note = data?['Note']?.toString() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _actionTile(
          Icons.flag_outlined,
          'Review $worstItem first',
          'This item is currently contributing the most waste in the report.',
          const Color(0xFFDC2626),
        ),
        const SizedBox(height: 10),
        _actionTile(
          Icons.check_circle_outline_rounded,
          'Keep prepared and sold entries daily',
          'The ML waste number becomes stronger when canteen actuals are logged every day.',
          const Color(0xFF0F766E),
        ),
        const SizedBox(height: 10),
        _actionTile(
          Icons.info_outline_rounded,
          'Data source',
          note.isEmpty ? 'Using the latest available waste analytics.' : note,
          const Color(0xFF2563EB),
        ),
      ],
    );
  }

  Widget _actionTile(
    IconData icon,
    String title,
    String subtitle,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: color, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    height: 1.35,
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
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 920;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('Waste Monitoring'),
        centerTitle: true,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: fetchWasteReport,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : data == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    errorMessage ?? 'Could not load waste metrics.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : RefreshIndicator(
                onRefresh: fetchWasteReport,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    isWide ? 28 : 16,
                    16,
                    isWide ? 28 : 16,
                    28,
                  ),
                  children: [
                    _heroCard(),
                    const SizedBox(height: 18),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth > 980
                            ? 4
                            : constraints.maxWidth > 620
                            ? 2
                            : 1;
                        final gap = columns == 1 ? 0.0 : 12.0;
                        final cardWidth =
                            (constraints.maxWidth - gap * (columns - 1)) /
                            columns;
                        return Wrap(
                          spacing: gap,
                          runSpacing: 12,
                          children: [
                            _metricCard(
                              label: 'Total Prepared',
                              value: _value('Total Prepared'),
                              icon: Icons.restaurant_rounded,
                              color: const Color(0xFF2563EB),
                              width: cardWidth,
                              helper: 'All portions prepared',
                            ),
                            _metricCard(
                              label: 'Total Sold',
                              value: _value('Total Sold'),
                              icon: Icons.shopping_bag_rounded,
                              color: const Color(0xFF16A34A),
                              width: cardWidth,
                              helper: 'Actual demand met',
                            ),
                            _metricCard(
                              label: 'Total Wasted',
                              value: _value('Total Wasted'),
                              icon: Icons.delete_outline_rounded,
                              color: const Color(0xFFDC2626),
                              width: cardWidth,
                              helper: 'Prepared but not sold',
                            ),
                            _metricCard(
                              label: 'Waste Rate',
                              value: _value('Waste Percentage', fallback: '0%'),
                              icon: Icons.percent_rounded,
                              color: const Color(0xFFF97316),
                              width: cardWidth,
                              helper: 'Waste divided by prepared',
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    if (isWide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _sectionCard(
                              title: 'ML Waste Impact',
                              icon: Icons.trending_down_rounded,
                              child: _impactComparison(),
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: _sectionCard(
                              title: 'Item Waste Watchlist',
                              icon: Icons.warning_amber_rounded,
                              child: _itemWasteList(),
                            ),
                          ),
                        ],
                      )
                    else ...[
                      _sectionCard(
                        title: 'ML Waste Impact',
                        icon: Icons.trending_down_rounded,
                        child: _impactComparison(),
                      ),
                      const SizedBox(height: 18),
                      _sectionCard(
                        title: 'Item Waste Watchlist',
                        icon: Icons.warning_amber_rounded,
                        child: _itemWasteList(),
                      ),
                    ],
                    const SizedBox(height: 18),
                    if (isWide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _sectionCard(
                              title: 'Waste Reduction Trend',
                              icon: Icons.stacked_line_chart_rounded,
                              child: _trendSection(),
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: _sectionCard(
                              title: 'Admin Action Notes',
                              icon: Icons.task_alt_rounded,
                              child: _adminActions(),
                            ),
                          ),
                        ],
                      )
                    else ...[
                      _sectionCard(
                        title: 'Waste Reduction Trend',
                        icon: Icons.stacked_line_chart_rounded,
                        child: _trendSection(),
                      ),
                      const SizedBox(height: 18),
                      _sectionCard(
                        title: 'Admin Action Notes',
                        icon: Icons.task_alt_rounded,
                        child: _adminActions(),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}
