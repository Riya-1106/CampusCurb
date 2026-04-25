import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/auth_service.dart';
import '../../services/campus_service.dart';
import '../../services/security_audit_service.dart';
import '../student/student_shell.dart';
import '../canteen/canteen_dashboard.dart';
import '../faculty/faculty_dashboard.dart';
import '../admin/admin_dashboard.dart';
import '../../utils/password_validator.dart';
import 'college_access_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final AuthService _authService = AuthService();
  final CampusService _campusService = CampusService();
  final SecurityAuditService _auditService = SecurityAuditService();
  bool _obscurePassword = true;
  String _selectedRole = 'student';
  static const String allowedDomain = 'sfit.ac.in';
  static const Set<String> adminAllowedEmails = {'campuscurb30@gmail.com'};

  bool _looksLikeEmail(String email) {
    final normalized = email.trim().toLowerCase();
    final atIndex = normalized.lastIndexOf('@');
    if (atIndex <= 0 || atIndex >= normalized.length - 3) {
      return false;
    }
    final host = normalized.substring(atIndex + 1);
    return host.contains('.');
  }

  bool _isAllowedForSelectedRole(String email) {
    final normalized = email.trim().toLowerCase();
    if (_selectedRole == 'admin') {
      return adminAllowedEmails.contains(normalized) || _looksLikeEmail(email);
    }
    return _looksLikeEmail(normalized);
  }

  Future<void> _logAttempt({
    required String email,
    required String method,
    required bool success,
    required String reason,
  }) async {
    await _auditService.logLoginAttempt(
      email: email,
      method: method,
      success: success,
      reason: reason,
      selectedRole: _selectedRole,
    );
  }

  Future<void> _routeByRole(String role) async {
    if (role == 'student') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const StudentShell()),
      );
    } else if (role == 'canteen') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const CanteenDashboard()),
      );
    } else if (role == 'admin') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AdminDashboard()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const FacultyDashboard()),
      );
    }
  }

  Future<String?> _validateProvisionedRole(User user) async {
    final data = await _campusService.getCurrentProfile();
    if (data == null) {
      return null;
    }
    final role = data['role']?.toString().toLowerCase();
    final isActive = data['isActive'];
    if (isActive is bool && !isActive) {
      return null;
    }
    return role;
  }

  Future<void> _forgotPassword() async {
    final seedEmail = _emailController.text.trim().toLowerCase();
    final emailController = TextEditingController(text: seedEmail);

    final enteredEmail = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Reset Password'),
          content: TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Registered Email',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext, emailController.text.trim());
              },
              child: const Text('Send Code'),
            ),
          ],
        );
      },
    );

    final email = (enteredEmail ?? '').trim().toLowerCase();
    if (email.isEmpty || !_looksLikeEmail(email)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid registered email.')),
      );
      return;
    }

    try {
      await _authService.sendPasswordResetEmail(email);
      await _logAttempt(
        email: email,
        method: 'password-reset',
        success: true,
        reason: 'Reset code sent',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Password reset email sent. Use the code/link in your email to set a new password.',
          ),
        ),
      );
    } on FirebaseAuthException catch (e) {
      await _logAttempt(
        email: email,
        method: 'password-reset',
        success: false,
        reason: e.code,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Failed to send reset email.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // 🔷 TOP GRADIENT HEADER
              Container(
                height: 200,
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF4A90E2), Color(0xFF357ABD)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(30),
                    bottomRight: Radius.circular(30),
                  ),
                ),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.fastfood, size: 50, color: Colors.white),
                      SizedBox(height: 10),
                      Text(
                        "CampusCurb",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        "Welcome Back",
                        style: TextStyle(fontSize: 14, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 30),

              // 🔷 LOGIN CARD
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 400),
                        child: Column(
                          children: [
                            // EMAIL
                            TextField(
                              controller: _emailController,
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.email_outlined),
                                labelText: "Email",
                                border: OutlineInputBorder(),
                              ),
                            ),

                            const SizedBox(height: 18),

                            // PASSWORD
                            TextField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.lock_outline),
                                labelText: "Password",
                                border: const OutlineInputBorder(),
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
                            ),

                            const SizedBox(height: 18),

                            // ROLE SELECTION
                            DropdownButtonFormField<String>(
                              initialValue: _selectedRole,
                              decoration: const InputDecoration(
                                labelText: 'Role',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() {
                                    _selectedRole = value;
                                  });
                                }
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
                                  value: 'admin',
                                  child: Text('Admin'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            const Text(
                              'Account access is managed by the administrator.\nPlease contact admin if you do not have an account.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.black54,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 20),

                            // LOGIN BUTTON
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF4A90E2),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                onPressed: () async {
                                  final messenger = ScaffoldMessenger.of(
                                    context,
                                  );
                                  final email = _emailController.text.trim();
                                  final password = _passwordController.text
                                      .trim();

                                  final passwordValidation =
                                      PasswordValidator.validateForLogin(
                                        password,
                                      );
                                  if (passwordValidation != null) {
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(passwordValidation),
                                      ),
                                    );
                                    return;
                                  }

                                  if (!_isAllowedForSelectedRole(email)) {
                                    await _logAttempt(
                                      email: email,
                                      method: 'password',
                                      success: false,
                                      reason: 'Blocked domain',
                                    );
                                    messenger.showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Enter a valid email address.',
                                        ),
                                      ),
                                    );
                                    return;
                                  }

                                  User? user;
                                  try {
                                    user = await _authService.login(
                                      email,
                                      password,
                                    );
                                  } on FirebaseAuthException catch (e) {
                                    await _logAttempt(
                                      email: email,
                                      method: 'password',
                                      success: false,
                                      reason: e.code,
                                    );
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          e.message ??
                                              'Login failed: ${e.code}',
                                        ),
                                      ),
                                    );
                                  }

                                  if (user != null) {
                                    final role = await _validateProvisionedRole(
                                      user,
                                    );

                                    if (role == null) {
                                      await _logAttempt(
                                        email: email,
                                        method: 'password',
                                        success: false,
                                        reason:
                                            'Account not provisioned or disabled',
                                      );
                                      messenger.showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'No account found. Contact admin.',
                                          ),
                                        ),
                                      );
                                      await _authService.logout();
                                      return;
                                    }

                                    if (role != _selectedRole) {
                                      await _logAttempt(
                                        email: email,
                                        method: 'password',
                                        success: false,
                                        reason:
                                            'Role mismatch. Actual: $role, selected: $_selectedRole',
                                      );
                                      await _authService.logout();
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Your account role is $role. Select the correct role to continue.',
                                          ),
                                        ),
                                      );
                                      return;
                                    }

                                    await _logAttempt(
                                      email: email,
                                      method: 'password',
                                      success: true,
                                      reason: 'Login success',
                                    );
                                    if (!mounted) return;
                                    await _routeByRole(role);
                                  } else {
                                    await _logAttempt(
                                      email: email,
                                      method: 'password',
                                      success: false,
                                      reason: 'Unknown login failure',
                                    );
                                    messenger.showSnackBar(
                                      const SnackBar(
                                        content: Text("Login failed"),
                                      ),
                                    );
                                  }
                                },
                                child: const Text(
                                  "Login",
                                  style: TextStyle(fontSize: 16),
                                ),
                              ),
                            ),

                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _forgotPassword,
                                child: const Text('Forgot password?'),
                              ),
                            ),

                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.login),
                                label: const Text('Sign in with Google'),
                                onPressed: () async {
                                  final messenger = ScaffoldMessenger.of(
                                    context,
                                  );
                                  final inputEmail = _emailController.text
                                      .trim();
                                  try {
                                    final user = await _authService
                                        .signInWithGoogle(
                                          allowedDomain,
                                          enforceDomain: false,
                                        );
                                    if (user == null) {
                                      await _logAttempt(
                                        email: inputEmail,
                                        method: 'google',
                                        success: false,
                                        reason: 'User cancelled Google sign-in',
                                      );
                                      return;
                                    }

                                    final email = user.email ?? inputEmail;
                                    final role = await _validateProvisionedRole(
                                      user,
                                    );

                                    if (role == null) {
                                      await _logAttempt(
                                        email: email,
                                        method: 'google',
                                        success: false,
                                        reason:
                                            'Account not provisioned or disabled',
                                      );
                                      messenger.showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Your account is not provisioned. Contact admin.',
                                          ),
                                        ),
                                      );
                                      await _authService.logout();
                                      return;
                                    }

                                    if (role != _selectedRole) {
                                      await _logAttempt(
                                        email: email,
                                        method: 'google',
                                        success: false,
                                        reason:
                                            'Role mismatch. Actual: $role, selected: $_selectedRole',
                                      );
                                      await _authService.logout();
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Your account role is $role. Select the correct role to continue.',
                                          ),
                                        ),
                                      );
                                      return;
                                    }

                                    await _logAttempt(
                                      email: email,
                                      method: 'google',
                                      success: true,
                                      reason: 'Login success',
                                    );
                                    if (!mounted) return;
                                    await _routeByRole(role);
                                  } on FirebaseAuthException catch (e) {
                                    await _logAttempt(
                                      email: inputEmail,
                                      method: 'google',
                                      success: false,
                                      reason: e.code,
                                    );
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          e.message ?? 'Google sign-in failed.',
                                        ),
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                            const SizedBox(height: 24),
                            TextButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const CollegeAccessScreen(),
                                  ),
                                );
                              },
                              child: const Text(
                                'College login or signup request',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
