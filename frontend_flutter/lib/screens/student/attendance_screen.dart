import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AttendanceScreen extends StatelessWidget {
  const AttendanceScreen({super.key});

  Future<void> markAttendance(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final now = DateTime.now();
    final today = "${now.year}-${now.month}-${now.day}";

    // Check if attendance already exists
    final query = await FirebaseFirestore.instance
        .collection('attendance')
        .where('uid', isEqualTo: user.uid)
        .where('date', isEqualTo: today)
        .get();

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .update({
      'points': FieldValue.increment(5)
    });

    if (query.docs.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Attendance already marked today")),
      );
      return;
    }

    // Mark attendance
    await FirebaseFirestore.instance.collection('attendance').add({
      'uid': user.uid,
      'date': today,
      'time': "${now.hour}:${now.minute}",
      'points': 5,
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Attendance marked successfully")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Mark Attendance")),
      body: Center(
        child: ElevatedButton(
          onPressed: () => markAttendance(context),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
          ),
          child: const Text(
            "Mark Today's Attendance",
            style: TextStyle(fontSize: 16),
          ),
        ),
      ),
    );
  }
}
