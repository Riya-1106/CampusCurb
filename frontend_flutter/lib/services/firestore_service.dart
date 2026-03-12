import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<String?> getUserRole() async {
    User? user = FirebaseAuth.instance.currentUser;

    if (user == null) return null;

    DocumentSnapshot doc = await _db.collection('users').doc(user.uid).get();

    return doc['role'];
  }
}
