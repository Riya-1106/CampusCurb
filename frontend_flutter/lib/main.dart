import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';

import 'screens/auth/login_screen.dart';
import 'screens/landing/landing_screen.dart';
import 'screens/student/student_shell.dart';
import 'screens/canteen/canteen_dashboard.dart';
import 'screens/college/college_dashboard.dart';
import 'screens/faculty/faculty_dashboard.dart';
import 'screens/admin/admin_dashboard.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'services/notification_service.dart';

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

class RoleBasedRouter extends StatelessWidget {
  const RoleBasedRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const LoginScreen();
    }

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const LoginScreen();
        }

        final data = snapshot.data!.data() as Map<String, dynamic>?;
        if (data == null || !data.containsKey('role')) {
          return const LoginScreen();
        }

        final role = data['role'];

        if (role == 'student') {
          return const StudentShell();
        } else if (role == 'canteen') {
          return const CanteenDashboard();
        } else if (role == 'admin') {
          return const AdminDashboard();
        } else if (role == 'faculty') {
          return const FacultyDashboard();
        } else if (role == 'college') {
          return const CollegeDashboard();
        } else {
          return const LoginScreen();
        }
      },
    );
  }
}
