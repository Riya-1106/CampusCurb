import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../services/college_exchange_service.dart';
import '../../../services/security_audit_service.dart';

class FoodExchangeRequestsScreen extends StatefulWidget {
  const FoodExchangeRequestsScreen({super.key});

  @override
  State<FoodExchangeRequestsScreen> createState() =>
      _FoodExchangeRequestsScreenState();
}

class _FoodExchangeRequestsScreenState
    extends State<FoodExchangeRequestsScreen> {
  final CollegeExchangeService _collegeExchangeService =
      CollegeExchangeService();
  final SecurityAuditService _auditService = SecurityAuditService();

  bool _isLoading = false;
  bool _isUpdating = false;
  String? _errorMessage;
  List<Map<String, dynamic>> _signupRequests = [];
  List<Map<String, dynamic>> _pendingListings = [];
  List<Map<String, dynamic>> _foodRequests = [];
  Map<String, dynamic> _summary = {};

  @override
  void initState() {
    super.initState();
    _loadExchangeRequests();
  }

  Future<void> _loadExchangeRequests() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
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
        _summary = Map<String, dynamic>.from(data['summary'] ?? {});
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading requests: $e')));
      }
    }
  }

  Future<void> _updateRequestStatus(
    String requestId,
    String status,
    String type, {
    String rejectionNote = '',
  }) async {
    if (_isUpdating) return; // Prevent duplicate requests

    setState(() {
      _isUpdating = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final token = await user.getIdToken();
      await _collegeExchangeService.updateExchangeStatus(
        requestId,
        status,
        token!,
        rejectionNote: rejectionNote,
      );

      await _auditService.logAdminAction(
        adminId: user.uid,
        action: 'update_exchange_status',
        targetId: requestId,
        details:
            'Updated $type status to $status${rejectionNote.isNotEmpty ? ' with reason: $rejectionNote' : ''}',
      );

      await _loadExchangeRequests();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$type ${status.toUpperCase()} successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error updating status: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    }
  }

  Future<void> _showRejectionDialog(String requestId, String type) async {
    final noteController = TextEditingController();

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Please provide a reason for rejection:'),
            const SizedBox(height: 16),
            TextField(
              controller: noteController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Enter rejection reason...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Colors.grey[50],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final note = noteController.text.trim();
              Navigator.pop(context);
              _updateRequestStatus(
                requestId,
                'rejected',
                type,
                rejectionNote: note,
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryHeader() {
    Widget tile(String label, dynamic value, Color color, IconData icon) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 10),
              Text(
                '${value ?? 0}',
                style: TextStyle(
                  color: color,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(color: Color(0xFF475569))),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Inter-college food sharing',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Canteen waste becomes surplus listings. Admin approves, then partner colleges can request pickup.',
            style: TextStyle(color: Colors.white70, height: 1.35),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              tile(
                'Pending surplus',
                _summary['pending_surplus_listings'] ??
                    _pendingListings
                        .where((e) => e['status'] == 'pending')
                        .length,
                Colors.white,
                Icons.inventory_2_outlined,
              ),
              const SizedBox(width: 10),
              tile(
                'Food requests',
                _summary['pending_food_requests'] ??
                    _foodRequests.where((e) => e['status'] == 'pending').length,
                Colors.white,
                Icons.swap_horiz_rounded,
              ),
            ],
          ),
        ],
      ),
    );
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
              const Text('No college signup requests right now.')
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
              'Surplus Food Listings',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (_pendingListings.isEmpty)
              const Text(
                'No surplus listings yet. Wasted food from canteen logs will appear here.',
              )
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

  Widget _buildFoodRequests() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'College Food Requests',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Approve these when a receiving college should collect food from the source college/canteen.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 16),
            if (_foodRequests.isEmpty)
              const Text('No inter-college food requests yet.')
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _foodRequests.length,
                itemBuilder: (context, index) {
                  final request = _foodRequests[index];
                  return _buildRequestCard(request, 'food_request');
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> request, String type) {
    Color statusColor = Colors.grey;
    String statusText =
        request['status']?.toString().toUpperCase() ?? 'UNKNOWN';

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

    final isSignup = type == 'signup';
    final isListing = type == 'listing';
    final title = isSignup
        ? request['college_name'] ?? 'Unknown College'
        : request['food_item'] ?? 'Unknown Item';

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
                    title.toString(),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
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
            if (isSignup) ...[
              _buildDetailRow('Contact', request['contact_name']),
              _buildDetailRow('Email', request['email']),
              _buildDetailRow('Phone', request['phone'] ?? 'Not provided'),
              if (request['allowed_domains'] != null)
                _buildDetailRow(
                  'Domains',
                  (request['allowed_domains'] as List).join(', '),
                ),
              if (request['notes'] != null &&
                  request['notes'].toString().isNotEmpty)
                _buildDetailRow('Notes', request['notes']),
            ] else if (isListing) ...[
              _buildDetailRow(
                'Source',
                request['college_name'] ?? request['collegeName'] ?? 'Unknown',
              ),
              _buildDetailRow(
                'Quantity',
                '${request['remaining_quantity'] ?? request['quantity']} / ${request['quantity']} ${request['unit'] ?? 'units'}',
              ),
              if (request['source'] == 'canteen_waste')
                _buildDetailRow('Created from', 'Canteen waste log'),
              if (request['pickup_window'] != null &&
                  request['pickup_window'].toString().isNotEmpty)
                _buildDetailRow('Pickup', request['pickup_window']),
              if (request['notes'] != null &&
                  request['notes'].toString().isNotEmpty)
                _buildDetailRow('Notes', request['notes']),
            ] else ...[
              _buildDetailRow('From', request['college_from'] ?? 'Unknown'),
              _buildDetailRow('To', request['college_to'] ?? 'Unknown'),
              _buildDetailRow(
                'Quantity',
                '${request['quantity']} ${request['unit'] ?? 'units'}',
              ),
              if (request['notes'] != null &&
                  request['notes'].toString().isNotEmpty)
                _buildDetailRow('Notes', request['notes']),
            ],
            const SizedBox(height: 12),
            if (request['status'] == 'pending')
              Row(
                children: [
                  ElevatedButton(
                    onPressed: _isUpdating
                        ? null
                        : () => _updateRequestStatus(
                            request['id'],
                            'approved',
                            type,
                          ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                    child: _isUpdating
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Approve'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _isUpdating
                        ? null
                        : () => _showRejectionDialog(request['id'], type),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    child: const Text('Reject'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, dynamic value) {
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
          Expanded(child: Text(value?.toString() ?? '')),
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
                    _buildSummaryHeader(),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Card(
                        color: const Color(0xFFFFFBEB),
                        child: ListTile(
                          leading: const Icon(
                            Icons.info_outline_rounded,
                            color: Color(0xFFB45309),
                          ),
                          title: const Text(
                            'Exchange data could not fully load',
                          ),
                          subtitle: Text(_errorMessage!),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    _buildSignupRequests(),
                    const SizedBox(height: 16),
                    _buildPendingListings(),
                    const SizedBox(height: 16),
                    _buildFoodRequests(),
                  ],
                ),
              ),
            ),
    );
  }
}
