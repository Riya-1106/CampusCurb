import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  Future<String> _fetchReward(int points) async {
    try {
      final response = await http.get(
        Uri.parse("http://10.0.2.2:8000/rewards/$points"),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['reward'] ?? "No reward";
      }
    } catch (_) {
      // ignore errors and fall back
    }

    return "No reward";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Leaderboard")),

      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .orderBy('points', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final users = snapshot.data!.docs;

          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];

              final points = (user['points'] ?? 0) as int;

              return FutureBuilder<String>(
                future: _fetchReward(points),
                builder: (context, rewardSnapshot) {
                  final rewardText = rewardSnapshot.data ?? 'Loading...';

                  return ListTile(
                    leading: CircleAvatar(child: Text("${index + 1}")),
                    title: Text(user['email']),
                    subtitle: Text(rewardText),
                    trailing: Text(
                      "${points} pts",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
