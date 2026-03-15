import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isAllowedDomain(String email, String allowedDomain) {
    final normalized = email.trim().toLowerCase();
    final atIndex = normalized.lastIndexOf('@');
    if (atIndex <= 0 || atIndex == normalized.length - 1) {
      return false;
    }
    final host = normalized.substring(atIndex + 1);
    final target = allowedDomain.trim().toLowerCase();
    return host == target || host.endsWith('.$target');
  }

  // Register (admin-managed accounts only; not used by normal users)
  Future<User?> register(String email, String password) async {
    final userCredential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    return userCredential.user;
  }

  // Login email/password
  Future<User?> login(String email, String password) async {
    final userCredential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    return userCredential.user;
  }

  // Google sign in
  Future<User?> signInWithGoogle(
    String allowedDomain, {
    bool enforceDomain = true,
  }) async {
    UserCredential userCredential;

    if (kIsWeb) {
      final provider = GoogleAuthProvider();
      userCredential = await _auth.signInWithPopup(provider);
    } else {
      final googleSignIn = GoogleSignIn.instance;
      await googleSignIn.initialize();
      final googleUser = await googleSignIn.authenticate();

      final googleAuth = googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );
      userCredential = await _auth.signInWithCredential(credential);
    }

    final user = userCredential.user;
    if (user == null || user.email == null) {
      throw FirebaseAuthException(
        code: 'invalid-user',
        message: 'Google sign-in did not return a valid user.',
      );
    }

    final email = user.email!;

    if (enforceDomain && !_isAllowedDomain(email, allowedDomain)) {
      await logout();
      throw FirebaseAuthException(
        code: 'invalid-domain',
        message:
            'Only $allowedDomain accounts (including subdomains) are allowed.',
      );
    }

    return user;
  }

  // Logout
  Future<void> logout() async {
    await _auth.signOut();
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Ignore if Google session does not exist.
    }
  }

  // Current user
  User? get currentUser => _auth.currentUser;
}
