import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Create new user document
  Future<void> createUser({
    required String uid,
    required String email,
    required String role,
  }) async {
    await _db.collection('users').doc(uid).set({
      'email': email,
      'role': role,
      'points': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // Get user role
  Future<String?> getUserRole(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data()?['role'];
  }
}