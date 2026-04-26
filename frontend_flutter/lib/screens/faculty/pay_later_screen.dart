import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/campus_service.dart';
import '../../services/faculty_service.dart';

class PayLaterScreen extends StatefulWidget {
  const PayLaterScreen({super.key});

  @override
  State<PayLaterScreen> createState() => _PayLaterScreenState();
}

class _PayLaterScreenState extends State<PayLaterScreen> {
  final CampusService _campusService = CampusService();
  final FacultyService _facultyService = FacultyService();

  bool _loading = true;
  bool _paying = false;
  String _period = 'weekly';
  int _pendingAmount = 0;
  String _pendingMessage = '';
  List<Map<String, dynamic>> _menu = [];
  List<Map<String, dynamic>> _orders = [];
  String? _errorMessage;
  bool _menuLoadFailed = false;
  bool _summaryLoadFailed = false;
  bool _ordersLoadFailed = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  int _readInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  String _formatCurrency(int amount) => 'Rs.$amount';

  Future<void> _loadData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _errorMessage = 'Sign in again to load faculty pay-later details.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
      _menuLoadFailed = false;
      _summaryLoadFailed = false;
      _ordersLoadFailed = false;
    });

    try {
      Future<List<Map<String, dynamic>>> safeMenu() async {
        try {
          return await _campusService.getMenu();
        } catch (_) {
          _menuLoadFailed = true;
          return const [];
        }
      }

      Future<Map<String, dynamic>> safeSummary() async {
        try {
          return await _facultyService.getPendingSummary(
            facultyId: user.uid,
            period: _period,
          );
        } catch (_) {
          _summaryLoadFailed = true;
          return const {};
        }
      }

      Future<Map<String, dynamic>> safeOrders() async {
        try {
          return await _facultyService.getOrders(facultyId: user.uid);
        } catch (_) {
          _ordersLoadFailed = true;
          return const {};
        }
      }

      final results = await Future.wait<Object>([
        safeMenu(),
        safeSummary(),
        safeOrders(),
      ]);
      final menu = results[0] as List<Map<String, dynamic>>;
      final summary = results[1] as Map<String, dynamic>;
      final orders = results[2] as Map<String, dynamic>;

      if (!mounted) return;
      setState(() {
        _menu = menu;
        _orders = (orders['orders'] as List<dynamic>? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        _pendingAmount = _readInt(summary['total_pending']);
        _pendingMessage =
            summary['notification_message']?.toString() ??
            'Order first, then settle your canteen bill here.';
        if (_menuLoadFailed && _summaryLoadFailed && _ordersLoadFailed) {
          _errorMessage =
              'Faculty pay-later is taking longer than expected right now. Pull to refresh in a moment.';
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

  Future<void> _createOrder(Map<String, dynamic> item) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final itemName = item['name']?.toString() ?? 'Unknown Item';
    final unitPrice = _readInt(item['price']);

    if (unitPrice <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid menu item price.')));
      return;
    }

    try {
      final result = await _facultyService.createPayLaterOrder(
        facultyId: user.uid,
        itemName: itemName,
        unitPrice: unitPrice,
        quantity: 1,
      );
      if (!mounted) return;
      final orderToken = result['order_token']?.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            orderToken == null || orderToken.isEmpty
                ? '$itemName added to your pending bill.'
                : '$itemName ordered. Show token $orderToken at the canteen counter.',
          ),
        ),
      );
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not create the faculty order: ${error.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    }
  }

  Future<void> _payNow() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _paying = true;
    });

    try {
      await _facultyService.settleAllPending(facultyId: user.uid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pending faculty payment settled.')),
      );
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Payment failed: ${error.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _paying = false;
        });
      }
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
        title: const Text('Faculty Pay-Later'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadData,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? _buildErrorState()
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                children: [
                  if (_menuLoadFailed || _summaryLoadFailed || _ordersLoadFailed) ...[
                    _buildInfoBanner(
                      'Some faculty pay-later details are still loading, so this screen is showing the data that came back first.',
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
                      _summaryTile(
                        'Pending amount',
                        _formatCurrency(_pendingAmount),
                        Icons.account_balance_wallet_rounded,
                        const Color(0xFF2563EB),
                      ),
                      _summaryTile(
                        'Pending orders',
                        '${_orders.length}',
                        Icons.receipt_long_rounded,
                        const Color(0xFF7C3AED),
                      ),
                      _summaryTile(
                        'Menu choices',
                        '${_menu.length}',
                        Icons.restaurant_menu_rounded,
                        const Color(0xFF0F766E),
                      ),
                      _summaryTile(
                        'Reminder mode',
                        _period == 'weekly' ? 'Weekly' : 'Monthly',
                        Icons.schedule_rounded,
                        const Color(0xFFF97316),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (isWide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildSettlementCard()),
                        const SizedBox(width: 16),
                        Expanded(child: _buildOrdersCard()),
                      ],
                    )
                  else ...[
                    _buildSettlementCard(),
                    const SizedBox(height: 16),
                    _buildOrdersCard(),
                  ],
                  const SizedBox(height: 16),
                  _buildMenuCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildErrorState() {
    return RefreshIndicator(
      onRefresh: _loadData,
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
              _heroPill(
                _pendingAmount > 0 ? 'Payment pending' : 'No pending due',
                Icons.receipt_long_rounded,
              ),
              _heroPill('Faculty settlement flow', Icons.school_rounded),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Order from the live canteen menu now and settle the amount later in one place.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _pendingMessage,
            style: const TextStyle(
              color: Color(0xFFE0F2FE),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroPill(String label, IconData icon) {
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

  Widget _summaryTile(String title, String value, IconData icon, Color color) {
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

  Widget _buildSettlementCard() {
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
            'Settlement',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose how often reminders should frame your pending amount, then settle everything in one action.',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<String>(
            initialValue: _period,
            decoration: InputDecoration(
              labelText: 'Reminder period',
              prefixIcon: const Icon(Icons.schedule_rounded),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            items: const [
              DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
              DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
            ],
            onChanged: (value) async {
              if (value == null) return;
              setState(() {
                _period = value;
              });
              await _loadData();
            },
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _pendingAmount > 0 && !_paying ? _payNow : null,
            icon: _paying
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.payments_rounded),
            label: Text(_paying ? 'Settling...' : 'Pay All Pending'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersCard() {
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
            'Pending Orders',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 12),
          if (_orders.isEmpty)
            const Text(
              'No pending orders yet. Add an item below to start a pay-later bill.',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            )
          else
            ..._orders.take(5).map((order) {
              final items = (order['items'] as List<dynamic>? ?? const [])
                  .cast<Map>();
              final firstItem = items.isNotEmpty ? items.first : const {};
              final itemName = firstItem['name']?.toString() ?? 'Order';
              final quantity = _readInt(firstItem['quantity'], fallback: 1);
              final totalAmount = _readInt(order['total_amount']);
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
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
                            'Qty $quantity • ${_formatCurrency(totalAmount)}',
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if ((order['order_token']?.toString().isNotEmpty ??
                              false))
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Token ${order['order_token']}',
                                style: const TextStyle(
                                  color: Color(0xFF2563EB),
                                  fontWeight: FontWeight.w700,
                                ),
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

  Widget _buildMenuCard() {
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
          const SizedBox(height: 12),
          if (_menu.isEmpty)
            const Text(
              'No approved menu items are available yet.',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            )
          else
            ..._menu.map((item) {
              final name = item['name']?.toString() ?? 'Unnamed';
              final price = _readInt(item['price']);
              final category =
                  item['category']?.toString().toUpperCase() ?? 'GENERAL';

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
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
                            '$category • ${_formatCurrency(price)}',
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton(
                      onPressed: () => _createOrder(item),
                      child: const Text('Add'),
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
