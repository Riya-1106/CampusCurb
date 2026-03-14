import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Create new user document
  Future<void> createUser({
    required String uid,
    required String email,
    required String role,
    String name = '',
    String department = '',
  }) async {
    await _db.collection('users').doc(uid).set({
      'name': name,
      'email': email,
      'role': role,
      'points': 0,
      'department': department,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // Get user role
  Future<String?> getUserRole(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data()?['role'];
  }
}
