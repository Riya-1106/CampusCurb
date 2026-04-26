import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';

import 'screens/auth/login_screen.dart';
import 'screens/landing/landing_screen.dart';
import 'screens/student/student_shell.dart';
import 'screens/canteen/canteen_shell.dart';
import 'screens/college/college_dashboard.dart';
import 'screens/faculty/faculty_shell.dart';
import 'screens/admin/admin_shell.dart';
import 'services/notification_service.dart';
import 'services/campus_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final notificationService = NotificationService();
  FirebaseAuth.instance.authStateChanges().listen((user) {
    if (user != null) {
      notificationService.initializeForSignedInUser();
    }
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData) {
          return const RoleBasedRouter();
        }

        return const LandingScreen();
      },
    );
  }
}

class RoleBasedRouter extends StatefulWidget {
  const RoleBasedRouter({super.key});

  @override
  State<RoleBasedRouter> createState() => _RoleBasedRouterState();
}

class _RoleBasedRouterState extends State<RoleBasedRouter> {
  static const String _cachedRoleKey = 'cached_user_role';
  String? _cachedRole;
  bool _profileResolved = false;

  @override
  void initState() {
    super.initState();
    _loadCachedRole();
    _refreshProfileRole();
  }

  Future<void> _loadCachedRole() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString(_cachedRoleKey);
    if (!mounted) return;
    setState(() {
      _cachedRole = role;
    });
  }

  Future<void> _refreshProfileRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _profileResolved = true;
      });
      return;
    }

    final profile = await CampusService().getCurrentProfile();
    final role = profile?['role']?.toString().toLowerCase();
    if (role != null && role.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cachedRoleKey, role);
    }

    if (!mounted) return;
    setState(() {
      if (role != null && role.isNotEmpty) {
        _cachedRole = role;
      }
      _profileResolved = true;
    });
  }

  Widget _screenForRole(String role) {
    switch (role) {
      case 'student':
        return const StudentShell();
      case 'canteen':
        return const CanteenShell();
      case 'admin':
        return const AdminShell();
      case 'faculty':
        return const FacultyShell();
      case 'college':
        return const CollegeDashboard();
      default:
        return const LoginScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const LoginScreen();
    }

    if (_cachedRole != null && _cachedRole!.isNotEmpty) {
      return _screenForRole(_cachedRole!);
    }

    if (!_profileResolved) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return const LoginScreen();
  }
}
