import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class WasteScreen extends StatefulWidget {
  const WasteScreen({super.key});

  @override
  State<WasteScreen> createState() => _WasteScreenState();
}

class _WasteScreenState extends State<WasteScreen> {

  final TextEditingController foodController = TextEditingController();
  final TextEditingController quantityController = TextEditingController();

  Future<void> addWaste() async {

    if (foodController.text.isEmpty || quantityController.text.isEmpty) {
      return;
    }

    await FirebaseFirestore.instance.collection('waste_reports').add({
      "food": foodController.text,
      "quantity": quantityController.text,
      "time": DateTime.now()
    });

    foodController.clear();
    quantityController.clear();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Waste recorded")),
    );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: const Text("Food Waste Tracking"),
      ),

      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [

            TextField(
              controller: foodController,
              decoration: const InputDecoration(
                labelText: "Food Item",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 20),

            TextField(
              controller: quantityController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Quantity Wasted",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: addWaste,
              child: const Text("Record Waste"),
            )
          ],
        ),
      ),
    );
  }
}