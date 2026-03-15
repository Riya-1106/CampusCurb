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
  String _period = 'weekly';
  int _pendingAmount = 0;
  String _pendingMessage = '';
  List<Map<String, dynamic>> _menu = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      final menu = await _campusService.getMenu();
      final summary = await _facultyService.getPendingSummary(
        facultyId: user.uid,
        period: _period,
      );

      if (!mounted) return;
      setState(() {
        _menu = menu;
        _pendingAmount = (summary['total_pending'] ?? 0) as int;
        _pendingMessage =
            summary['notification_message']?.toString() ??
            'No pending payment.';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load pay-later data: $e')),
      );
    }
  }

  Future<void> _createOrder(Map<String, dynamic> item) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final itemName = item['name']?.toString() ?? 'Unknown Item';
    final unitPrice = item['price'] is int
        ? item['price'] as int
        : int.tryParse(item['price']?.toString() ?? '') ?? 0;

    if (unitPrice <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid menu item price.')));
      return;
    }

    try {
      await _facultyService.createPayLaterOrder(
        facultyId: user.uid,
        itemName: itemName,
        unitPrice: unitPrice,
        quantity: 1,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$itemName added to pay-later orders.')),
      );
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Order failed: $e')));
    }
  }

  Future<void> _payNow() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await _facultyService.settleAllPending(facultyId: user.uid);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Pending payment settled.')));
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Payment failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Faculty Pay-Later')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Pending Canteen Payment',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '₹$_pendingAmount',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFB5482A),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _pendingMessage,
                            style: const TextStyle(color: Colors.black54),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: _period,
                                  decoration: const InputDecoration(
                                    labelText: 'Reminder Period',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'weekly',
                                      child: Text('Weekly'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'monthly',
                                      child: Text('Monthly'),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() {
                                        _period = value;
                                      });
                                      _loadData();
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              ElevatedButton(
                                onPressed: _pendingAmount > 0 ? _payNow : null,
                                child: const Text('Pay Now'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Approved Menu (Pay-Later)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  ..._menu.map((item) {
                    final name = item['name']?.toString() ?? 'Unnamed';
                    final price = item['price'] is int
                        ? item['price'] as int
                        : int.tryParse(item['price']?.toString() ?? '') ?? 0;
                    final category = item['category']?.toString() ?? 'general';

                    return Card(
                      child: ListTile(
                        title: Text(name),
                        subtitle: Text('₹$price • ${category.toUpperCase()}'),
                        trailing: ElevatedButton(
                          onPressed: () => _createOrder(item),
                          child: const Text('Order'),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}
