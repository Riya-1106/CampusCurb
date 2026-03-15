import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/college_exchange_service.dart';
import '../auth/college_access_screen.dart';
import '../shared/profile_screen.dart';

class CollegeDashboard extends StatefulWidget {
  const CollegeDashboard({super.key});

  @override
  State<CollegeDashboard> createState() => _CollegeDashboardState();
}

class _CollegeDashboardState extends State<CollegeDashboard> {
  final CollegeExchangeService _service = CollegeExchangeService();
  final AuthService _authService = AuthService();

  bool _isLoading = true;
  List<Map<String, dynamic>> _myListings = [];
  List<Map<String, dynamic>> _availableListings = [];
  List<Map<String, dynamic>> _myRequests = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final results = await Future.wait([
        _service.getMyListings(),
        _service.getAvailableListings(),
        _service.getMyRequests(),
      ]);
      _myListings = results[0];
      _availableListings = results[1];
      _myRequests = results[2];
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load college exchange data: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showCreateListingDialog() async {
    final rootContext = context;
    final foodController = TextEditingController();
    final quantityController = TextEditingController();
    final unitController = TextEditingController(text: 'plates');
    final pickupController = TextEditingController();
    final notesController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Post Surplus Food'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: foodController,
                decoration: const InputDecoration(labelText: 'Food Item'),
              ),
              TextField(
                controller: quantityController,
                decoration: const InputDecoration(labelText: 'Quantity'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: unitController,
                decoration: const InputDecoration(labelText: 'Unit'),
              ),
              TextField(
                controller: pickupController,
                decoration: const InputDecoration(labelText: 'Pickup Window'),
              ),
              TextField(
                controller: notesController,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);
              final quantity = int.tryParse(quantityController.text.trim());
              if (foodController.text.trim().isEmpty || quantity == null) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Enter a valid food item and quantity.'),
                  ),
                );
                return;
              }
              await _service.createListing(
                foodItem: foodController.text.trim(),
                quantity: quantity,
                unit: unitController.text.trim(),
                pickupWindow: pickupController.text.trim(),
                notes: notesController.text.trim(),
              );
              if (!context.mounted || !rootContext.mounted) return;
              navigator.pop();
              await _refresh();
              if (!rootContext.mounted) return;
              ScaffoldMessenger.of(rootContext).showSnackBar(
                const SnackBar(
                  content: Text('Listing sent for admin approval.'),
                ),
              );
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  Future<void> _showRequestDialog(Map<String, dynamic> listing) async {
    final rootContext = context;
    final quantityController = TextEditingController();
    final notesController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Request ${listing['food_item'] ?? 'Food'}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: quantityController,
              decoration: InputDecoration(
                labelText:
                    'Quantity (max ${listing['remaining_quantity'] ?? listing['quantity'] ?? 0})',
              ),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: notesController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);
              final quantity = int.tryParse(quantityController.text.trim());
              if (quantity == null || quantity <= 0) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Enter a valid quantity.')),
                );
                return;
              }
              await _service.requestFood(
                listingId: listing['id'].toString(),
                quantity: quantity,
                notes: notesController.text.trim(),
              );
              if (!context.mounted || !rootContext.mounted) return;
              navigator.pop();
              await _refresh();
              if (!rootContext.mounted) return;
              ScaffoldMessenger.of(rootContext).showSnackBar(
                const SnackBar(content: Text('Food request sent to admin.')),
              );
            },
            child: const Text('Request'),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(String title, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 6),
            Text(title, style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(color: Colors.black54)),
      ],
    );
  }

  Widget _buildListingCard(
    Map<String, dynamic> listing, {
    VoidCallback? action,
    String? actionLabel,
  }) {
    final status = listing['status']?.toString() ?? 'pending';
    final remaining = listing['remaining_quantity'] ?? listing['quantity'] ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              listing['food_item']?.toString() ?? 'Unknown item',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text('College: ${listing['college_name'] ?? 'Unknown'}'),
            Text('Quantity: $remaining ${listing['unit'] ?? ''}'),
            if ((listing['pickup_window'] ?? '').toString().isNotEmpty)
              Text('Pickup: ${listing['pickup_window']}'),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Chip(label: Text(status.toUpperCase())),
                if (action != null && actionLabel != null)
                  ElevatedButton(onPressed: action, child: Text(actionLabel)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> request) {
    return Card(
      child: ListTile(
        title: Text(
          '${request['food_item'] ?? 'Food'} • ${request['quantity'] ?? 0} ${request['unit'] ?? ''}',
        ),
        subtitle: Text(
          'From ${request['college_from'] ?? 'Unknown'} to ${request['college_to'] ?? 'Unknown'}\nStatus: ${request['status'] ?? 'pending'}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? 'college account';

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      appBar: AppBar(
        title: const Text('College Exchange Dashboard'),
        backgroundColor: const Color(0xFF0D6E6E),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
            icon: const Icon(Icons.person_outline),
          ),
          IconButton(
            onPressed: () async {
              await _authService.logout();
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const CollegeAccessScreen()),
                (route) => false,
              );
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateListingDialog,
        backgroundColor: const Color(0xFF0D6E6E),
        foregroundColor: Colors.white,
        label: const Text('Post Surplus'),
        icon: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    email,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Post leftover food for approval, then request approved surplus from other colleges.',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _summaryCard(
                        'My surplus listings',
                        '${_myListings.length}',
                        const Color(0xFF0D6E6E),
                      ),
                      const SizedBox(width: 12),
                      _summaryCard(
                        'Available from others',
                        '${_availableListings.length}',
                        const Color(0xFF2A7DE1),
                      ),
                      const SizedBox(width: 12),
                      _summaryCard(
                        'My exchange requests',
                        '${_myRequests.length}',
                        const Color(0xFFB5482A),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _sectionTitle(
                    'My Surplus Listings',
                    'These are the items your college has posted for admin review or exchange.',
                  ),
                  const SizedBox(height: 10),
                  if (_myListings.isEmpty)
                    const Card(
                      child: ListTile(
                        title: Text('No surplus listings posted yet.'),
                      ),
                    ),
                  ..._myListings.map((listing) => _buildListingCard(listing)),
                  const SizedBox(height: 20),
                  _sectionTitle(
                    'Approved Listings From Other Colleges',
                    'Only admin-approved surplus appears here for cross-college requests.',
                  ),
                  const SizedBox(height: 10),
                  if (_availableListings.isEmpty)
                    const Card(
                      child: ListTile(
                        title: Text(
                          'No approved listings available right now.',
                        ),
                      ),
                    ),
                  ..._availableListings.map(
                    (listing) => _buildListingCard(
                      listing,
                      action: () => _showRequestDialog(listing),
                      actionLabel: 'Request',
                    ),
                  ),
                  const SizedBox(height: 20),
                  _sectionTitle(
                    'My Request Activity',
                    'Track the food you requested from other colleges and requests raised against your surplus.',
                  ),
                  const SizedBox(height: 10),
                  if (_myRequests.isEmpty)
                    const Card(
                      child: ListTile(title: Text('No request activity yet.')),
                    ),
                  ..._myRequests.map(_buildRequestCard),
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }
}
