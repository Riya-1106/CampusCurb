import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/campus_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final CampusService _campusService = CampusService();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _departmentController = TextEditingController();
  final _collegeNameController = TextEditingController();
  final _collegeDomainsController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  String _role = '';
  String _email = '';

  bool get _showDepartmentField => _role == 'faculty' || _role == 'canteen';

  bool get _showCollegeFields => _role == 'college';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _departmentController.dispose();
    _collegeNameController.dispose();
    _collegeDomainsController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      Navigator.pop(context);
      return;
    }

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final data = doc.data() ?? <String, dynamic>{};
    _email = user.email ?? data['email']?.toString() ?? '';
    _role = data['role']?.toString().toLowerCase() ?? '';

    _nameController.text = data['name']?.toString() ?? '';
    _phoneController.text = data['phone']?.toString() ?? '';
    _departmentController.text = data['department']?.toString() ?? '';
    _collegeNameController.text =
        data['collegeName']?.toString() ?? data['name']?.toString() ?? '';

    final rawDomains = data['collegeDomains'];
    if (rawDomains is List) {
      _collegeDomainsController.text = rawDomains
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .join(', ');
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final payload = <String, dynamic>{
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      };

      if (_showDepartmentField) {
        payload['department'] = _departmentController.text.trim();
      }

      if (_showCollegeFields) {
        payload['collegeName'] = _collegeNameController.text.trim();
        payload['collegeDomains'] = _collegeDomainsController.text
            .split(RegExp(r'[,\s]+'))
            .map((d) => d.trim().toLowerCase().replaceFirst('@', ''))
            .where((d) => d.isNotEmpty)
            .toSet()
            .toList();
      }

      await _campusService.updateProfile(
        name: payload['name']?.toString() ?? '',
        phone: payload['phone']?.toString() ?? '',
        department: payload['department']?.toString(),
        collegeName: payload['collegeName']?.toString(),
        collegeDomains: (payload['collegeDomains'] as List<dynamic>?)
            ?.map((value) => value.toString())
            .toList(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update profile: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: const Text(
                    'Email cannot be changed here. Please contact admin for email updates.',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  readOnly: true,
                  initialValue: _email,
                  decoration: const InputDecoration(
                    labelText: 'Email (read-only)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  readOnly: true,
                  initialValue: _role,
                  decoration: const InputDecoration(
                    labelText: 'Role (read-only)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Phone (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_showDepartmentField) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _departmentController,
                    decoration: const InputDecoration(
                      labelText: 'Department (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                if (_showCollegeFields) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _collegeNameController,
                    decoration: const InputDecoration(
                      labelText: 'College Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _collegeDomainsController,
                    decoration: const InputDecoration(
                      labelText: 'College Domains (comma separated)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveProfile,
                    child: _isSaving
                        ? const CircularProgressIndicator()
                        : const Text('Save Changes'),
                  ),
                ),
              ],
            ),
    );
  }
}
