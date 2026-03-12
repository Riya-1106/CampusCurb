import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  Future<void> placeOrder(
      BuildContext context,
      String item,
      int price,
      ) async {

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection('orders').add({
      "uid": user.uid,
      "item": item,
      "price": price,
      "quantity": 1,
      "time": DateTime.now()
    });

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .update({
      'points': FieldValue.increment(2)
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("$item ordered successfully")),
    );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: const Text("Today's Menu"),
      ),

      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('menu')
            .snapshots(),
        builder: (context, snapshot) {

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final items = snapshot.data!.docs;

          if (items.isEmpty) {
            return const Center(child: Text("No menu available"));
          }

          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {

              final item = items[index];

              return Card(
                margin: const EdgeInsets.all(10),
                child: ListTile(
                  title: Text(item['name']),
                  subtitle: Text("₹${item['price']}"),
                  trailing: ElevatedButton(
                    onPressed: () {
                      placeOrder(
                        context,
                        item['name'],
                        item['price'],
                      );
                    },
                    child: const Text("Order"),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}