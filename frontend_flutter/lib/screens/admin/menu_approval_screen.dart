import 'package:flutter/material.dart';
import '../../services/admin_service.dart';

class MenuApprovalScreen extends StatefulWidget {
  const MenuApprovalScreen({super.key});

  @override
  State<MenuApprovalScreen> createState() => _MenuApprovalScreenState();
}

class _MenuApprovalScreenState extends State<MenuApprovalScreen> {
  final AdminService _adminService = AdminService();
  bool _isLoading = true;
  List<Map<String, dynamic>> _pendingItems = [];

  @override
  void initState() {
    super.initState();
    _loadPendingMenu();
  }

  Future<void> _loadPendingMenu() async {
    setState(() {
      _isLoading = true;
    });
    try {
      _pendingItems = await _adminService.getMenuPending();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load pending menu: $e')),
      );
      _pendingItems = [];
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _approveItem(String id) async {
    try {
      await _adminService.approveMenuItem(id);
      await _loadPendingMenu();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Menu item approved.')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Approve failed: $e')));
    }
  }

  Future<void> _rejectItem(String id) async {
    try {
      await _adminService.rejectMenuItem(id);
      await _loadPendingMenu();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Menu item rejected.')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Reject failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Menu Approvals')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _pendingItems.isEmpty
          ? const Center(child: Text('No menu items pending approval.'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _pendingItems.length,
              itemBuilder: (context, index) {
                final data = _pendingItems[index];
                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: ListTile(
                    title: Text(data['name']?.toString() ?? 'Unnamed'),
                    subtitle: Text(
                      'Price: ₹${data['price'] ?? 0} • ${data['category'] ?? 'General'}',
                    ),
                    trailing: Wrap(
                      spacing: 6,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.check, color: Colors.green),
                          onPressed: () => _approveItem(data['id'].toString()),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.red),
                          onPressed: () => _rejectItem(data['id'].toString()),
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
