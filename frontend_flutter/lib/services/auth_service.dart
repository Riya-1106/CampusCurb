import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

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
  Future<User?> signInWithGoogle(String allowedDomain) async {
    final googleSignIn = GoogleSignIn.instance;
    final googleUser = await googleSignIn.authenticate();
    final email = googleUser.email;

    if (!email.endsWith('@$allowedDomain')) {
      await googleSignIn.signOut();
      throw FirebaseAuthException(
        code: 'invalid-domain',
        message: 'Only @$allowedDomain accounts are allowed.',
      );
    }

    final googleAuth = googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );

    final userCredential = await _auth.signInWithCredential(credential);
    return userCredential.user;
  }

  // Logout
  Future<void> logout() async {
    await _auth.signOut();
    await GoogleSignIn.instance.signOut();
  }

  // Current user
  User? get currentUser => _auth.currentUser;
}
