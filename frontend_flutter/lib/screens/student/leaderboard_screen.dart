import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../services/prediction_service.dart';

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  Future<String> _fetchReward(int points) async {
    try {
      return await PredictionService().getReward(points);
    } catch (_) {
      return "No reward";
    }
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
                      "$points pts",
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
