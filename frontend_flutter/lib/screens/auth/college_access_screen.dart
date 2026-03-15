import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/college_exchange_service.dart';
import '../../services/security_audit_service.dart';
import '../college/college_dashboard.dart';
import 'login_screen.dart';

class CollegeAccessScreen extends StatefulWidget {
  const CollegeAccessScreen({super.key});

  @override
  State<CollegeAccessScreen> createState() => _CollegeAccessScreenState();
}

class _CollegeAccessScreenState extends State<CollegeAccessScreen>
    with SingleTickerProviderStateMixin {
  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();
  final _collegeNameController = TextEditingController();
  final _contactNameController = TextEditingController();
  final _signupEmailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _notesController = TextEditingController();
  final AuthService _authService = AuthService();
  final SecurityAuditService _auditService = SecurityAuditService();
  final CollegeExchangeService _collegeExchangeService =
      CollegeExchangeService();

  late final TabController _tabController;
  bool _obscurePassword = true;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _collegeNameController.dispose();
    _contactNameController.dispose();
    _signupEmailController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _logAttempt({
    required String email,
    required bool success,
    required String reason,
  }) {
    return _auditService.logLoginAttempt(
      email: email,
      method: 'password',
      success: success,
      reason: reason,
      selectedRole: 'college',
    );
  }

  Future<String?> _validateCollegeRole(User user) async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (!doc.exists) {
      return null;
    }

    final data = doc.data();
    final role = data?['role']?.toString().toLowerCase();
    final isActive = data?['isActive'];
    if (isActive is bool && !isActive) {
      return null;
    }
    return role;
  }

  Future<void> _loginCollege() async {
    final email = _loginEmailController.text.trim().toLowerCase();
    final password = _loginPasswordController.text.trim();
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter email and password.')),
      );
      return;
    }

    setState(() {
      _isBusy = true;
    });

    try {
      final user = await _authService.login(email, password);
      if (user == null) {
        await _logAttempt(
          email: email,
          success: false,
          reason: 'Unknown login failure',
        );
        return;
      }

      final role = await _validateCollegeRole(user);
      if (role != 'college') {
        await _logAttempt(
          email: email,
          success: false,
          reason: 'Role mismatch or college account not provisioned',
        );
        await _authService.logout();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This college account is not provisioned yet.'),
          ),
        );
        return;
      }

      await _logAttempt(
        email: email,
        success: true,
        reason: 'College login success',
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const CollegeDashboard()),
      );
    } on FirebaseAuthException catch (e) {
      await _logAttempt(email: email, success: false, reason: e.code);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message ?? 'Login failed.')));
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _submitSignupRequest() async {
    final collegeName = _collegeNameController.text.trim();
    final contactName = _contactNameController.text.trim();
    final email = _signupEmailController.text.trim().toLowerCase();
    if (collegeName.isEmpty || contactName.isEmpty || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('College name, contact name, and email are required.'),
        ),
      );
      return;
    }

    setState(() {
      _isBusy = true;
    });

    try {
      await _collegeExchangeService.submitSignupRequest(
        collegeName: collegeName,
        contactName: contactName,
        email: email,
        phone: _phoneController.text.trim(),
        notes: _notesController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Signup request sent to admin for review.'),
        ),
      );
      _collegeNameController.clear();
      _contactNameController.clear();
      _signupEmailController.clear();
      _phoneController.clear();
      _notesController.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Widget _input(
    TextEditingController controller,
    String label, {
    bool obscure = false,
    int maxLines = 1,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: suffixIcon,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FB),
      appBar: AppBar(
        title: const Text('College Portal'),
        backgroundColor: const Color(0xFF0D6E6E),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Separate access for partner colleges',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'College canteens sign up here, wait for admin review, then log in to post surplus food and request approved listings from other colleges.',
                          style: TextStyle(color: Colors.black54),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TabBar(
                        controller: _tabController,
                        tabs: const [
                          Tab(text: 'Login'),
                          Tab(text: 'Signup Request'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 420,
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            ListView(
                              children: [
                                _input(_loginEmailController, 'College Email'),
                                const SizedBox(height: 12),
                                _input(
                                  _loginPasswordController,
                                  'Password',
                                  obscure: _obscurePassword,
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: _isBusy ? null : _loginCollege,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0D6E6E),
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size.fromHeight(50),
                                  ),
                                  child: _isBusy
                                      ? const CircularProgressIndicator(
                                          color: Colors.white,
                                        )
                                      : const Text('Login to College Portal'),
                                ),
                              ],
                            ),
                            ListView(
                              children: [
                                _input(_collegeNameController, 'College Name'),
                                const SizedBox(height: 12),
                                _input(
                                  _contactNameController,
                                  'Contact Person',
                                ),
                                const SizedBox(height: 12),
                                _input(
                                  _signupEmailController,
                                  'Official Email',
                                ),
                                const SizedBox(height: 12),
                                _input(_phoneController, 'Phone (optional)'),
                                const SizedBox(height: 12),
                                _input(
                                  _notesController,
                                  'Notes for admin (optional)',
                                  maxLines: 4,
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: _isBusy
                                      ? null
                                      : _submitSignupRequest,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0D6E6E),
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size.fromHeight(50),
                                  ),
                                  child: _isBusy
                                      ? const CircularProgressIndicator(
                                          color: Colors.white,
                                        )
                                      : const Text('Send Signup Request'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LoginScreen(),
                            ),
                          );
                        },
                        child: const Text('Back to campus login'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
