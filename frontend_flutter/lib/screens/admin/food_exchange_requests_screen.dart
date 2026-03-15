import 'package:flutter/material.dart';
import '../../services/admin_service.dart';

class FoodExchangeRequestsScreen extends StatefulWidget {
  const FoodExchangeRequestsScreen({super.key});

  @override
  State<FoodExchangeRequestsScreen> createState() =>
      _FoodExchangeRequestsScreenState();
}

class _FoodExchangeRequestsScreenState
    extends State<FoodExchangeRequestsScreen> {
  final AdminService _adminService = AdminService();
  bool _isLoading = true;
  List<Map<String, dynamic>> _signupRequests = [];
  List<Map<String, dynamic>> _pendingListings = [];
  List<Map<String, dynamic>> _foodRequests = [];

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final payload = await _adminService.getExchangeRequests();
      _signupRequests = List<Map<String, dynamic>>.from(
        (payload['signup_requests'] as List<dynamic>? ?? []).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
      );
      _pendingListings = List<Map<String, dynamic>>.from(
        (payload['pending_listings'] as List<dynamic>? ?? []).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
      );
      _foodRequests = List<Map<String, dynamic>>.from(
        (payload['food_requests'] as List<dynamic>? ?? []).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
      );
    } catch (e) {
      _signupRequests = [];
      _pendingListings = [];
      _foodRequests = [];
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load requests: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updateStatus(String id, String status) async {
    try {
      await _adminService.updateExchangeStatus(id, status);
      await _loadRequests();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Request $status')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Update failed: $e')));
    }
  }

  Widget _statusActions(String id, String status) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.check, color: Colors.green),
          onPressed: status == 'approved'
              ? null
              : () => _updateStatus(id, 'approved'),
        ),
        IconButton(
          icon: const Icon(Icons.close, color: Colors.red),
          onPressed: status == 'rejected'
              ? null
              : () => _updateStatus(id, 'rejected'),
        ),
      ],
    );
  }

  Widget _sectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(color: Colors.black54)),
      ],
    );
  }

  Widget _emptyCard(String text) {
    return Card(child: ListTile(title: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('College Exchange Control')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadRequests,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _sectionHeader(
                    'College Signup Requests',
                    'Colleges submit access requests here before admin provisions login access.',
                  ),
                  const SizedBox(height: 8),
                  if (_signupRequests.isEmpty)
                    _emptyCard('No college signup requests yet.'),
                  ..._signupRequests.map((data) {
                    final status = data['status']?.toString() ?? 'pending';
                    return Card(
                      child: ListTile(
                        title: Text(
                          data['college_name']?.toString() ?? 'College',
                        ),
                        subtitle: Text(
                          'Contact: ${data['contact_name'] ?? 'Unknown'}\nEmail: ${data['email'] ?? 'Unknown'}\nStatus: $status',
                        ),
                        trailing: _statusActions(data['id'].toString(), status),
                      ),
                    );
                  }),
                  const SizedBox(height: 20),
                  _sectionHeader(
                    'Pending Surplus Listings',
                    'A college listing must be approved before other colleges can see it.',
                  ),
                  const SizedBox(height: 8),
                  if (_pendingListings.isEmpty)
                    _emptyCard('No surplus listings yet.'),
                  ..._pendingListings.map((data) {
                    final status = data['status']?.toString() ?? 'pending';
                    return Card(
                      child: ListTile(
                        title: Text(
                          data['food_item']?.toString() ?? 'Food listing',
                        ),
                        subtitle: Text(
                          'College: ${data['college_name'] ?? 'Unknown'}\nQuantity: ${data['remaining_quantity'] ?? data['quantity'] ?? 0} ${data['unit'] ?? ''}\nStatus: $status',
                        ),
                        trailing: _statusActions(data['id'].toString(), status),
                      ),
                    );
                  }),
                  const SizedBox(height: 20),
                  _sectionHeader(
                    'Cross-College Food Requests',
                    'Track which approved listings were requested and approve or reject fulfillment.',
                  ),
                  const SizedBox(height: 8),
                  if (_foodRequests.isEmpty)
                    _emptyCard('No cross-college requests yet.'),
                  ..._foodRequests.map((data) {
                    final status = data['status']?.toString() ?? 'pending';
                    return Card(
                      child: ListTile(
                        title: Text(
                          data['food_item']?.toString() ?? 'Food request',
                        ),
                        subtitle: Text(
                          'From: ${data['college_from'] ?? 'Unknown'}\nTo: ${data['college_to'] ?? 'Unknown'}\nQuantity: ${data['quantity'] ?? 0} ${data['unit'] ?? ''}\nStatus: $status',
                        ),
                        trailing: _statusActions(data['id'].toString(), status),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}
