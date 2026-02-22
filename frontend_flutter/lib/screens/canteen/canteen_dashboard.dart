import 'package:flutter/material.dart';

class CanteenDashboard extends StatelessWidget {
  const CanteenDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Canteen Dashboard")),
      body: const Center(child: Text("Welcome Canteen Staff 🧑‍🍳")),
    );
  }
}
