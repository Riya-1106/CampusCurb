import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Student Orders"),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .orderBy('time', descending: true)
            .snapshots(),
        builder: (context, snapshot) {

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final orders = snapshot.data!.docs;

          if (orders.isEmpty) {
            return const Center(child: Text("No orders yet"));
          }

          return ListView.builder(
            itemCount: orders.length,
            itemBuilder: (context, index) {

              final order = orders[index];

              return Card(
                margin: const EdgeInsets.all(10),
                child: ListTile(
                  title: Text(order['item']),
                  subtitle: Text(
                      "Qty: ${order['quantity']}  |  User: ${order['uid']}"),
                  trailing: Text("₹${order['price']}"),
                ),
              );
            },
          );
        },
      ),
    );
  }
}