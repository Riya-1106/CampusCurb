import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/admin_service.dart';
import '../../utils/password_validator.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _departmentController = TextEditingController();
  final _collegeNameController = TextEditingController();
  final _collegeDomainsController = TextEditingController();
  final AdminService _adminService = AdminService();

  String _selectedRole = 'student';
  bool _isCreating = false;

  bool get _isCollegeRole => _selectedRole == 'college';

  bool get _showDepartmentField =>
      _selectedRole == 'faculty' || _selectedRole == 'canteen';

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _departmentController.dispose();
    _collegeNameController.dispose();
    _collegeDomainsController.dispose();
    super.dispose();
  }

  Future<void> _createUser() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final collegeName = _collegeNameController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide email and password.')),
      );
      return;
    }

    if (_isCollegeRole && collegeName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('College name is required for college role.'),
        ),
      );
      return;
    }

    final passwordValidation = PasswordValidator.validateForCreation(password);
    if (passwordValidation != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(passwordValidation)));
      return;
    }

    setState(() {
      _isCreating = true;
    });

    try {
      final collegeDomains = _collegeDomainsController.text
          .split(RegExp(r'[,\s]+'))
          .map((d) => d.trim().toLowerCase().replaceFirst('@', ''))
          .where((d) => d.isNotEmpty)
          .toSet()
          .toList();

      await _adminService.createManagedUser(
        email: email,
        password: password,
        role: _selectedRole,
        name: _nameController.text.trim(),
        department: _showDepartmentField
            ? _departmentController.text.trim()
            : '',
        collegeName: _isCollegeRole ? collegeName : '',
        collegeDomains: _isCollegeRole ? collegeDomains : const [],
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Created $_selectedRole account for $email.')),
      );

      _nameController.clear();
      _departmentController.clear();
      _collegeNameController.clear();
      _collegeDomainsController.clear();
      _emailController.clear();
      _passwordController.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Create failed: ${e.toString()}')));
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  Future<void> _deleteUser(String docId) async {
    await FirebaseFirestore.instance.collection('users').doc(docId).delete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('User Management')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Create Managed Account',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Fields adapt by role. College-only fields appear only for college role.',
                      style: TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedRole,
                      decoration: const InputDecoration(
                        labelText: 'Role',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _selectedRole = value;
                          if (!_isCollegeRole) {
                            _collegeNameController.clear();
                            _collegeDomainsController.clear();
                          }
                          if (!_showDepartmentField) {
                            _departmentController.clear();
                          }
                        });
                      },
                      items: const [
                        DropdownMenuItem(
                          value: 'student',
                          child: Text('Student'),
                        ),
                        DropdownMenuItem(
                          value: 'faculty',
                          child: Text('Faculty'),
                        ),
                        DropdownMenuItem(
                          value: 'canteen',
                          child: Text('Canteen'),
                        ),
                        DropdownMenuItem(
                          value: 'college',
                          child: Text('College'),
                        ),
                        DropdownMenuItem(value: 'admin', child: Text('Admin')),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Name (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (_showDepartmentField) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: _departmentController,
                        decoration: const InputDecoration(
                          labelText: 'Department (optional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    if (_isCollegeRole) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: _collegeNameController,
                        decoration: const InputDecoration(
                          labelText: 'College Name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _collegeDomainsController,
                        decoration: const InputDecoration(
                          labelText: 'College Domains (comma separated)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      PasswordValidator.strongPasswordHint,
                      style: TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: _isCreating ? null : _createUser,
                      child: _isCreating
                          ? const CircularProgressIndicator()
                          : const Text('Create Account'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Existing Users',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final users = snapshot.data!.docs;
                  if (users.isEmpty) {
                    return const Center(child: Text('No users yet.'));
                  }

                  return ListView.builder(
                    itemCount: users.length,
                    itemBuilder: (context, index) {
                      final doc = users[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final email = data['email'] ?? 'Unknown';
                      final role = data['role'] ?? 'unknown';
                      return Card(
                        child: ListTile(
                          title: Text(email.toString()),
                          subtitle: Text('Role: $role'),
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.delete_forever,
                              color: Colors.red,
                            ),
                            onPressed: () async {
                              await _deleteUser(doc.id);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('User record removed.'),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
