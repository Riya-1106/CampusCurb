import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  Map<String, dynamic>? data;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    fetchAnalytics();
  }

  Future<void> fetchAnalytics() async {
    final response = await http.get(
      Uri.parse("http://10.0.2.2:8000/waste-analytics"),
    );

    if (response.statusCode == 200) {
      setState(() {
        data = json.decode(response.body);
        loading = false;
      });
    }
  }

  Widget analyticsCard(String title, String value, IconData icon) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: Colors.blue),

            const SizedBox(height: 10),

            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),

            const SizedBox(height: 5),

            Text(
              value,
              style: const TextStyle(fontSize: 18, color: Colors.black87),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Canteen Analytics"), centerTitle: true),

      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),

              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 15,
                mainAxisSpacing: 15,

                children: [
                  analyticsCard(
                    "Food Prepared",
                    data!["total_food_prepared"].toString(),
                    Icons.restaurant,
                  ),

                  analyticsCard(
                    "Food Sold",
                    data!["total_food_sold"].toString(),
                    Icons.shopping_cart,
                  ),

                  analyticsCard(
                    "Food Wasted",
                    data!["total_food_wasted"].toString(),
                    Icons.delete,
                  ),

                  analyticsCard(
                    "Waste %",
                    data!["waste_percentage"].toString(),
                    Icons.percent,
                  ),

                  analyticsCard(
                    "Waste After ML",
                    data!["estimated_waste_after_ml"].toString(),
                    Icons.auto_graph,
                  ),

                  analyticsCard(
                    "Waste Reduced",
                    data!["estimated_reduction"].toString(),
                    Icons.eco,
                  ),
                ],
              ),
            ),
    );
  }
}
