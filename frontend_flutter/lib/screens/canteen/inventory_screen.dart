import 'package:flutter/material.dart';

import '../../services/prediction_service.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final PredictionService _service = PredictionService();
  final Map<String, TextEditingController> _preparedControllers = {};
  final Map<String, TextEditingController> _soldControllers = {};
  final Map<String, TextEditingController> _wastedControllers = {};
  final Map<String, TextEditingController> _notesControllers = {};

  static const List<String> _timeSlots = [
    '09:00-11:00',
    '11:00-13:00',
    '13:00-15:00',
    '15:00+',
  ];

  DateTime _selectedDate = DateTime.now();
  String _selectedTimeSlot = '11:00-13:00';
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic>? _summary;
  bool _loading = true;
  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadOperations();
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _disposeControllers() {
    for (final controller in _preparedControllers.values) {
      controller.dispose();
    }
    for (final controller in _soldControllers.values) {
      controller.dispose();
    }
    for (final controller in _wastedControllers.values) {
      controller.dispose();
    }
    for (final controller in _notesControllers.values) {
      controller.dispose();
    }
    _preparedControllers.clear();
    _soldControllers.clear();
    _wastedControllers.clear();
    _notesControllers.clear();
  }

  String get _selectedDateKey =>
      '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';

  String _prettyDate(DateTime date) {
    const monthNames = [
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
    return '${date.day} ${monthNames[date.month - 1]} ${date.year}';
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

  String _itemKey(Map<String, dynamic> item) =>
      item['food_item']?.toString().trim().toLowerCase() ?? '';

  void _updateAutoWaste(String key) {
    final prepared = int.tryParse(_preparedControllers[key]?.text.trim() ?? '');
    final sold = int.tryParse(_soldControllers[key]?.text.trim() ?? '');
    final wastedController = _wastedControllers[key];
    if (wastedController == null) return;

    final nextWaste = prepared == null || sold == null
        ? ''
        : (prepared - sold).clamp(0, 999999).toString();
    if (wastedController.text == nextWaste) return;
    wastedController.text = nextWaste;
  }

  void _setControllersFromItems(List<Map<String, dynamic>> items) {
    _disposeControllers();
    for (final item in items) {
      final key = _itemKey(item);
      _preparedControllers[key] = TextEditingController(
        text: _readInt(item['quantity_prepared']) > 0
            ? _readInt(item['quantity_prepared']).toString()
            : '',
      );
      _soldControllers[key] = TextEditingController(
        text: _readInt(item['quantity_sold']) > 0
            ? _readInt(item['quantity_sold']).toString()
            : '',
      );
      _wastedControllers[key] = TextEditingController(
        text: _readInt(item['quantity_wasted']) > 0
            ? _readInt(item['quantity_wasted']).toString()
            : '',
      );
      _notesControllers[key] = TextEditingController(
        text: item['notes']?.toString() ?? '',
      );
      _preparedControllers[key]!.addListener(() => _updateAutoWaste(key));
      _soldControllers[key]!.addListener(() => _updateAutoWaste(key));
      _updateAutoWaste(key);
    }
  }

  Future<void> _loadOperations({bool showLoader = true}) async {
    if (showLoader) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      final payload = await _service.getCanteenOperations(
        date: _selectedDateKey,
        timeSlot: _selectedTimeSlot,
      );
      final items =
          (payload['items'] as List<dynamic>? ?? const [])
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
      _setControllersFromItems(items);
      if (!mounted) return;
      setState(() {
        _items = items;
        _summary = Map<String, dynamic>.from(
          payload['summary'] as Map<String, dynamic>? ?? {},
        );
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

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked == null) return;
    setState(() {
      _selectedDate = picked;
    });
    await _loadOperations();
  }

  List<Map<String, dynamic>> _buildSavePayload() {
    return _items.map((item) {
      final key = _itemKey(item);
      final preparedText = _preparedControllers[key]?.text.trim() ?? '';
      final soldText = _soldControllers[key]?.text.trim() ?? '';
      final wastedText = _wastedControllers[key]?.text.trim() ?? '';
      final notes = _notesControllers[key]?.text.trim() ?? '';
      return <String, dynamic>{
        'food_item': item['food_item'],
        'food_category': item['food_category'],
        'price': _readInt(item['price']),
        'predicted_demand': _readInt(item['predicted_demand']),
        'suggested_preparation': _readInt(item['suggested_preparation']),
        'confidence_score': _readDouble(item['confidence_score']),
        'confidence_label': item['confidence_label']?.toString() ?? 'Low',
        'weather_type': item['weather_type']?.toString() ?? 'Sunny',
        'temperature': _readInt(item['temperature'], fallback: 29),
        'quantity_prepared': int.tryParse(preparedText) ?? 0,
        'quantity_sold': int.tryParse(soldText) ?? 0,
        'quantity_wasted': wastedText.isEmpty ? null : int.tryParse(wastedText) ?? 0,
        'notes': notes,
      };
    }).toList();
  }

  Future<void> _saveOperations() async {
    setState(() {
      _saving = true;
    });

    try {
      final result = await _service.saveCanteenOperations(
        date: _selectedDateKey,
        timeSlot: _selectedTimeSlot,
        items: _buildSavePayload(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result['message'] ?? 'Saved'} • ${result['saved_count'] ?? 0} item(s) updated',
          ),
        ),
      );
      _loadOperations(showLoader: false);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Widget _summaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
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
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
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

  Widget _numberField({
    required String label,
    required TextEditingController controller,
    bool readOnly = false,
    String? helperText,
  }) {
    return SizedBox(
      width: 130,
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          helperText: helperText,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          isDense: true,
          filled: readOnly,
          fillColor: readOnly ? const Color(0xFFF8FAFC) : null,
        ),
      ),
    );
  }

  Widget _buildItemCard(Map<String, dynamic> item) {
    final key = _itemKey(item);
    final confidenceScore = _readDouble(item['confidence_score']);
    final confidenceLabel = item['confidence_label']?.toString() ?? 'Low';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['food_item']?.toString() ?? 'Menu item',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${item['food_category'] ?? 'General'} • Predicted ${_readInt(item['predicted_demand'])} • Suggested ${_readInt(item['suggested_preparation'])}',
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
                  color: (confidenceLabel == 'High'
                          ? const Color(0xFFDCFCE7)
                          : confidenceLabel == 'Medium'
                          ? const Color(0xFFFEF3C7)
                          : const Color(0xFFFEE2E2))
                      .withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$confidenceLabel ${confidenceScore.toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: confidenceLabel == 'High'
                        ? const Color(0xFF15803D)
                        : confidenceLabel == 'Medium'
                        ? const Color(0xFFB45309)
                        : const Color(0xFFB91C1C),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _numberField(
                label: 'Prepared',
                controller: _preparedControllers[key]!,
              ),
              _numberField(
                label: 'Sold',
                controller: _soldControllers[key]!,
              ),
              _numberField(
                label: 'Wasted',
                controller: _wastedControllers[key]!,
                readOnly: true,
                helperText: 'Auto',
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesControllers[key],
            minLines: 1,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Notes for this item',
              hintText: 'Stockout, event crowd, rain, item finished early...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Recent avg ${_readDouble(item['recent_average_sales']).toStringAsFixed(1)} • ${item['recommended_action'] ?? ''}',
            style: const TextStyle(
              color: Color(0xFF475569),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: const Text('Operations Log'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadOperations,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: FilledButton.icon(
            onPressed: _saving || _loading ? null : _saveOperations,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving...' : 'Save Prepared / Sold / Wasted'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(child: Text(_errorMessage!))
          : RefreshIndicator(
              onRefresh: _loadOperations,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
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
                        const Text(
                          'Capture today’s production and sales',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Enter prepared quantity before service, sold quantity during service, and waste at the end. These values feed prediction accuracy and waste analytics.',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 15,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _pickDate,
                              icon: const Icon(Icons.calendar_today_outlined),
                              label: Text(_prettyDate(_selectedDate)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white38),
                              ),
                            ),
                            DropdownButtonHideUnderline(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.white38),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: DropdownButton<String>(
                                  value: _selectedTimeSlot,
                                  dropdownColor: const Color(0xFF0F172A),
                                  style: const TextStyle(color: Colors.white),
                                  iconEnabledColor: Colors.white,
                                  items: _timeSlots
                                      .map(
                                        (slot) => DropdownMenuItem(
                                          value: slot,
                                          child: Text(slot),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) async {
                                    if (value == null) return;
                                    setState(() {
                                      _selectedTimeSlot = value;
                                    });
                                    await _loadOperations();
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _summaryCard(
                          'Items with input',
                          '${_readInt(_summary?['records_with_inputs'])}',
                          Icons.fact_check_outlined,
                          const Color(0xFF2563EB),
                        ),
                        const SizedBox(width: 12),
                        _summaryCard(
                          'Prepared total',
                          '${_readInt(_summary?['total_prepared'])}',
                          Icons.inventory_2_outlined,
                          const Color(0xFF15803D),
                        ),
                        const SizedBox(width: 12),
                        _summaryCard(
                          'Sold total',
                          '${_readInt(_summary?['total_sold'])}',
                          Icons.shopping_bag_outlined,
                          const Color(0xFF7C3AED),
                        ),
                        const SizedBox(width: 12),
                        _summaryCard(
                          'Waste total',
                          '${_readInt(_summary?['total_wasted'])}',
                          Icons.delete_outline,
                          const Color(0xFFB91C1C),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_items.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 18,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Text(
                        'No forecast items are available for this date and slot yet.',
                        style: TextStyle(
                          color: Color(0xFF475569),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  else
                    ..._items.map(_buildItemCard),
                ],
              ),
            ),
    );
  }
}
