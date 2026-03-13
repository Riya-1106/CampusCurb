import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  Future<void> placeOrder(BuildContext context, String item, int price) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection('orders').add({
      "uid": user.uid,
      "item": item,
      "price": price,
      "quantity": 1,
      "time": DateTime.now(),
    });

    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'points': FieldValue.increment(2),
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text("$item ordered successfully")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Today's Menu")),

      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('menu').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final items = snapshot.data!.docs;

          final menuItems = items.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data.containsKey('name') && data.containsKey('price');
          }).toList();

          if (menuItems.isEmpty) {
            return const Center(child: Text("No menu available"));
          }

          return ListView.builder(
            itemCount: menuItems.length,
            itemBuilder: (context, index) {
              final doc = menuItems[index];
              final data = doc.data() as Map<String, dynamic>;
              final itemName = (data['name'] ?? 'Unnamed Item').toString();

              final priceValue = data['price'];
              final itemPrice = priceValue is int
                  ? priceValue
                  : int.tryParse(priceValue?.toString() ?? '') ?? 0;

              return Card(
                margin: const EdgeInsets.all(10),
                child: ListTile(
                  title: Text(itemName),
                  subtitle: Text("₹$itemPrice"),
                  trailing: ElevatedButton(
                    onPressed: itemPrice > 0
                        ? () {
                            placeOrder(context, itemName, itemPrice);
                          }
                        : null,
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
