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
  List<Map<String, dynamic>> _requests = [];

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
      _requests = await _adminService.getExchangeRequests();
    } catch (e) {
      _requests = [];
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load requests: $e')));
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _updateStatus(String id, String status) async {
    try {
      await _adminService.updateExchangeStatus(id, status);
      await _loadRequests();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Request $status')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Update failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Food Exchange Requests')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _requests.isEmpty
          ? const Center(child: Text('No exchange requests yet.'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _requests.length,
              itemBuilder: (context, index) {
                final data = _requests[index];
                final status = data['status'] ?? 'pending';
                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: ListTile(
                    title: Text(
                      data['title']?.toString() ?? 'Food exchange request',
                    ),
                    subtitle: Text(
                      'Student: ${data['requestedBy'] ?? 'Unknown'} • Status: $status',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.check, color: Colors.green),
                          onPressed: status == 'approved'
                              ? null
                              : () => _updateStatus(
                                  data['id'].toString(),
                                  'approved',
                                ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.red),
                          onPressed: status == 'rejected'
                              ? null
                              : () => _updateStatus(
                                  data['id'].toString(),
                                  'rejected',
                                ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
