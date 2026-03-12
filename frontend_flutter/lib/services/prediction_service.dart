import 'package:cloud_firestore/cloud_firestore.dart';

class PredictionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<List<Map<String, dynamic>>> getPredictions() async {
    QuerySnapshot snapshot = await _firestore.collection('predictions').get();
    return snapshot.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();
  }

  Future<void> addPrediction(Map<String, dynamic> prediction) async {
    await _firestore.collection('predictions').add(prediction);
  }
}