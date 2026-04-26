import 'package:flutter/material.dart';

import '../../services/prediction_service.dart';

class OrderQueueScreen extends StatefulWidget {
  const OrderQueueScreen({super.key});

  @override
  State<OrderQueueScreen> createState() => _OrderQueueScreenState();
}

class _OrderQueueScreenState extends State<OrderQueueScreen> {
  final PredictionService _service = PredictionService();

  bool _loading = true;
  bool _refreshing = false;
  String _filter = 'pending';
  String? _errorMessage;
  List<Map<String, dynamic>> _orders = [];
  Map<String, dynamic> _summary = {};
  final Set<String> _updatingKeys = <String>{};

  @override
  void initState() {
    super.initState();
    _loadQueue();
  }

  int _readInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  Future<void> _loadQueue() async {
    setState(() {
      _loading = _orders.isEmpty && _summary.isEmpty;
      _refreshing = _orders.isNotEmpty || _summary.isNotEmpty;
      _errorMessage = null;
    });

    try {
      final payload = await _service.getCanteenOrderQueue();
      if (!mounted) return;
      setState(() {
        _orders = (payload['orders'] as List<dynamic>? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        _summary = Map<String, dynamic>.from(
          payload['summary'] as Map<String, dynamic>? ?? {},
        );
        _loading = false;
        _refreshing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        if (_orders.isEmpty) {
          _errorMessage = error.toString().replaceFirst('Exception: ', '');
        }
      });
    }
  }

  List<Map<String, dynamic>> get _visibleOrders {
    if (_filter == 'all') return _orders;
    return _orders
        .where((order) => order['pickup_status']?.toString() == _filter)
        .toList();
  }

  String _formatCurrency(int amount) => 'Rs.$amount';

  String _formatStatusLabel(String value) {
    switch (value) {
      case 'ready':
        return 'Ready';
      case 'collected':
        return 'Collected';
      default:
        return 'Pending';
    }
  }

  Color _statusColor(String value) {
    switch (value) {
      case 'ready':
        return const Color(0xFF2563EB);
      case 'collected':
        return const Color(0xFF0F766E);
      default:
        return const Color(0xFFF97316);
    }
  }

  String _entryKey(Map<String, dynamic> order) {
    final source = order['source']?.toString() ?? 'student';
    final token = order['order_token']?.toString() ?? '';
    final orderId =
        order['order_id']?.toString() ??
        order['entry_id']?.toString() ??
        '';
    return '$source:${token.isNotEmpty ? token : orderId}';
  }

  Future<void> _updateStatus(
    Map<String, dynamic> order,
    String nextStatus,
  ) async {
    final entryKey = _entryKey(order);
    setState(() {
      _updatingKeys.add(entryKey);
    });

    try {
      await _service.updateCanteenOrderQueueStatus(
        source: order['source']?.toString() ?? 'student',
        pickupStatus: nextStatus,
        orderToken: order['order_token']?.toString(),
        orderId: order['order_id']?.toString(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Token ${order['order_token'] ?? order['order_id']} marked ${_formatStatusLabel(nextStatus).toLowerCase()}.',
          ),
        ),
      );
      await _loadQueue();
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
          _updatingKeys.remove(entryKey);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: const Text('Pickup Queue'),
        actions: [
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: (_loading || _refreshing) ? null : _loadQueue,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? _buildErrorState()
          : RefreshIndicator(
              onRefresh: _loadQueue,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  _buildSummaryStrip(),
                  const SizedBox(height: 16),
                  _buildFilterRow(),
                  const SizedBox(height: 16),
                  if (_visibleOrders.isEmpty) _buildEmptyState(),
                  ..._visibleOrders.map(_buildOrderCard),
                ],
              ),
            ),
    );
  }

  Widget _buildErrorState() {
    return RefreshIndicator(
      onRefresh: _loadQueue,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Container(
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
                    _errorMessage!,
                    style: const TextStyle(
                      color: Color(0xFF9A3412),
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryStrip() {
    final cards = [
      (
        'Pending',
        '${_readInt(_summary['pending_count'])}',
        Icons.hourglass_top_rounded,
        const Color(0xFFF97316),
      ),
      (
        'Ready',
        '${_readInt(_summary['ready_count'])}',
        Icons.local_mall_rounded,
        const Color(0xFF2563EB),
      ),
      (
        'Collected',
        '${_readInt(_summary['collected_count'])}',
        Icons.check_circle_rounded,
        const Color(0xFF0F766E),
      ),
      (
        'Faculty',
        '${_readInt(_summary['faculty_count'])}',
        Icons.school_rounded,
        const Color(0xFF7C3AED),
      ),
    ];

    return SizedBox(
      height: 118,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final (label, value, icon, color) = cards[index];
          return Container(
            width: 138,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                const Spacer(),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterRow() {
    const filters = [
      ('pending', 'Pending'),
      ('ready', 'Ready'),
      ('collected', 'Collected'),
      ('all', 'All'),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: filters.map((entry) {
        final selected = _filter == entry.$1;
        return ChoiceChip(
          label: Text(entry.$2),
          selected: selected,
          onSelected: (_) {
            setState(() {
              _filter = entry.$1;
            });
          },
          labelStyle: TextStyle(
            fontWeight: FontWeight.w700,
            color: selected ? const Color(0xFF2563EB) : const Color(0xFF475569),
          ),
          selectedColor: const Color(0xFFDFF3FF),
          backgroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        );
      }).toList(),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.inbox_rounded,
            size: 34,
            color: Color(0xFF94A3B8),
          ),
          SizedBox(height: 10),
          Text(
            'No orders in this queue right now.',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final source = order['source']?.toString() ?? 'student';
    final token =
        order['display_token']?.toString() ??
        order['order_token']?.toString() ??
        order['order_id']?.toString() ??
        '-';
    final pickupStatus = order['pickup_status']?.toString() ?? 'pending';
    final color = _statusColor(pickupStatus);
    final updating = _updatingKeys.contains(_entryKey(order));
    final items = (order['items'] as List<dynamic>? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      token,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      source == 'faculty'
                          ? 'Faculty pay-later pickup'
                          : 'Student prepaid pickup',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _formatStatusLabel(pickupStatus),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _metaPill(
                '${_readInt(order['total_quantity'])} item(s)',
                Icons.shopping_bag_outlined,
              ),
              _metaPill(
                _formatCurrency(_readInt(order['total_amount'])),
                Icons.currency_rupee_rounded,
              ),
              _metaPill(
                source == 'faculty'
                    ? 'Payment ${order['payment_status'] ?? 'pending'}'
                    : 'Payment paid',
                Icons.payments_outlined,
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item['name']?.toString() ?? 'Item',
                      style: const TextStyle(
                        color: Color(0xFF334155),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    'x${_readInt(item['quantity'])}',
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: updating || pickupStatus == 'pending'
                    ? null
                    : () => _updateStatus(order, 'pending'),
                icon: const Icon(Icons.undo_rounded, size: 18),
                label: const Text('Set Pending'),
              ),
              FilledButton.icon(
                onPressed: updating || pickupStatus == 'ready'
                    ? null
                    : () => _updateStatus(order, 'ready'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                ),
                icon: updating && pickupStatus != 'ready'
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.notifications_active_rounded, size: 18),
                label: const Text('Mark Ready'),
              ),
              FilledButton.icon(
                onPressed: updating || pickupStatus == 'collected'
                    ? null
                    : () => _updateStatus(order, 'collected'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                ),
                icon: const Icon(Icons.check_circle_rounded, size: 18),
                label: const Text('Collected'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metaPill(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF64748B)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
