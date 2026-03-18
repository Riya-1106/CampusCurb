import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../services/college_exchange_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/security_audit_service.dart';

class FoodExchangeRequestsScreen extends StatefulWidget {
  const FoodExchangeRequestsScreen({super.key});

  @override
  State<FoodExchangeRequestsScreen> createState() => _FoodExchangeRequestsScreenState();
}

class _FoodExchangeRequestsScreenState extends State<FoodExchangeRequestsScreen> {
  final CollegeExchangeService _collegeExchangeService = CollegeExchangeService();
  final AuthService _authService = AuthService();
  final SecurityAuditService _auditService = SecurityAuditService();
  
  bool _isLoading = false;
  List<Map<String, dynamic>> _signupRequests = [];
  List<Map<String, dynamic>> _pendingListings = [];
  List<Map<String, dynamic>> _foodRequests = [];

  @override
  void initState() {
    super.initState();
    _loadExchangeRequests();
  }

  Future<void> _loadExchangeRequests() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final token = await user.getIdToken();
      final data = await _collegeExchangeService.getExchangeRequests(token!);

      setState(() {
        _signupRequests = data['signup_requests'] ?? [];
        _pendingListings = data['pending_listings'] ?? [];
        _foodRequests = data['food_requests'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading requests: $e')),
        );
      }
    }
  }

  Future<void> _updateRequestStatus(String requestId, String status, String type) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final token = await user.getIdToken();
      await _collegeExchangeService.updateExchangeStatus(requestId, status, token!);

      await _auditService.logAdminAction(
        adminId: user.uid,
        action: 'update_exchange_status',
        targetId: requestId,
        details: 'Updated $type status to $status',
      );

      await _loadExchangeRequests();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$type ${status.toUpperCase()} successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating status: $e')),
        );
      }
    }
  }

  Widget _buildSignupRequests() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'College Signup Requests',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (_signupRequests.isEmpty)
              const Text('No pending signup requests')
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _signupRequests.length,
                itemBuilder: (context, index) {
                  final request = _signupRequests[index];
                  return _buildRequestCard(request, 'signup');
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingListings() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pending Food Listings',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (_pendingListings.isEmpty)
              const Text('No pending food listings')
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _pendingListings.length,
                itemBuilder: (context, index) {
                  final listing = _pendingListings[index];
                  return _buildRequestCard(listing, 'listing');
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> request, String type) {
    Color statusColor = Colors.grey;
    String statusText = request['status']?.toString().toUpperCase() ?? 'UNKNOWN';
    
    switch (request['status']) {
      case 'pending':
        statusColor = Colors.orange;
        break;
      case 'approved':
        statusColor = Colors.green;
        break;
      case 'rejected':
        statusColor = Colors.red;
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    type == 'signup' 
                        ? request['college_name'] ?? 'Unknown College'
                        : request['food_item'] ?? 'Unknown Item',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (type == 'signup') ...[
              _buildDetailRow('Contact', request['contact_name']),
              _buildDetailRow('Email', request['email']),
              _buildDetailRow('Phone', request['phone'] ?? 'Not provided'),
              if (request['allowed_domains'] != null)
                _buildDetailRow('Domains', (request['allowed_domains'] as List).join(', ')),
              if (request['notes'] != null && request['notes'].toString().isNotEmpty)
                _buildDetailRow('Notes', request['notes']),
            ] else ...[
              _buildDetailRow('College', request['collegeName'] ?? 'Unknown'),
              _buildDetailRow('Quantity', '${request['quantity']} ${request['unit'] ?? 'units'}'),
              if (request['pickup_window'] != null && request['pickup_window'].toString().isNotEmpty)
                _buildDetailRow('Pickup', request['pickup_window']),
              if (request['notes'] != null && request['notes'].toString().isNotEmpty)
                _buildDetailRow('Notes', request['notes']),
            ],
            const SizedBox(height: 12),
            if (request['status'] == 'pending')
              Row(
                children: [
                  ElevatedButton(
                    onPressed: () => _updateRequestStatus(request['id'], 'approved', type),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    child: const Text('Approve'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _updateRequestStatus(request['id'], 'rejected', type),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    child: const Text('Reject'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Food Exchange Requests'),
        backgroundColor: const Color(0xFF0D6E6E),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadExchangeRequests,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildSignupRequests(),
                    const SizedBox(height: 16),
                    _buildPendingListings(),
                  ],
                ),
              ),
            ),
    );
  }
}
