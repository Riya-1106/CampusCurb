import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PredictionScreen extends StatelessWidget {
  const PredictionScreen({super.key});

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: const Text("Food Analytics"),
      ),

      body: FutureBuilder<QuerySnapshot>(
        future: FirebaseFirestore.instance.collection('orders').get(),
        builder: (context, snapshot) {

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final orders = snapshot.data!.docs.length;

          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [

                const Icon(
                  Icons.analytics,
                  size: 80,
                  color: Colors.blue,
                ),

                const SizedBox(height: 20),

                Text(
                  "Total Orders Today",
                  style: Theme.of(context).textTheme.titleLarge,
                ),

                const SizedBox(height: 10),

                Text(
                  orders.toString(),
                  style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 30),

                const Text(
                  "ML Prediction coming soon",
                  style: TextStyle(color: Colors.grey),
                )
              ],
            ),
          );
        },
      ),
    );
  }
}