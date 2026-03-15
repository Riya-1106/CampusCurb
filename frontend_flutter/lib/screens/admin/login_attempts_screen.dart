import 'package:flutter/material.dart';

import '../../services/admin_service.dart';

class LoginAttemptsScreen extends StatefulWidget {
  const LoginAttemptsScreen({super.key});

  @override
  State<LoginAttemptsScreen> createState() => _LoginAttemptsScreenState();
}

class _LoginAttemptsScreenState extends State<LoginAttemptsScreen> {
  final AdminService _adminService = AdminService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _attempts = [];

  @override
  void initState() {
    super.initState();
    _loadAttempts();
  }

  Future<void> _loadAttempts() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await _adminService.getLoginAttempts();
      setState(() {
        _attempts = data;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login Security Logs'),
        actions: [
          IconButton(onPressed: _loadAttempts, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : _attempts.isEmpty
          ? const Center(child: Text('No login attempts recorded yet.'))
          : ListView.builder(
              itemCount: _attempts.length,
              itemBuilder: (context, index) {
                final item = _attempts[index];
                final success = item['success'] == true;
                final email = item['email']?.toString() ?? 'unknown';
                final method = item['method']?.toString() ?? 'unknown';
                final reason = item['reason']?.toString() ?? '';
                final role = item['selected_role']?.toString() ?? '';
                final timestamp = item['timestamp']?.toString() ?? '';

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: ListTile(
                    leading: Icon(
                      success ? Icons.check_circle : Icons.warning_amber,
                      color: success ? Colors.green : Colors.red,
                    ),
                    title: Text(email),
                    subtitle: Text(
                      '$timestamp\nMethod: $method | Role: $role\n$reason',
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            ),
    );
  }
}
