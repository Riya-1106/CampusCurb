import 'package:flutter/material.dart';

import '../../services/prediction_service.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final PredictionService _service = PredictionService();
  Map<String, dynamic>? wasteData;
  Map<String, dynamic>? studentData;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    fetchAnalytics();
  }

  Future<void> fetchAnalytics() async {
    try {
      final wasteResult = await _service.getWasteReport();
      final studentResult = await _service.getStudentAnalytics();

      setState(() {
        wasteData = wasteResult;
        studentData = studentResult;
        loading = false;
      });
    } catch (_) {
      setState(() {
        loading = false;
      });
    }
  }

  Widget analyticsCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              color.withValues(alpha: 0.1),
              color.withValues(alpha: 0.2),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text("Campus Analytics Overview"),
        centerTitle: true,
        backgroundColor: const Color(0xFF4A90E2),
      ),

      body: SafeArea(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  children: [
                    // 🔷 TOP HEADER
                    Container(
                      height: 120,
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF4A90E2), Color(0xFF357ABD)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(30),
                          bottomRight: Radius.circular(30),
                        ),
                      ),
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.insights, size: 40, color: Colors.white),
                            SizedBox(height: 10),
                            Text(
                              "Campus Insights",
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: 5),
                            Text(
                              "Comprehensive analytics dashboard",
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // 🔷 WASTE ANALYTICS SECTION
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Waste Management",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          GridView.count(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount: 2,
                            crossAxisSpacing: 15,
                            mainAxisSpacing: 15,
                            children: [
                              analyticsCard(
                                "Total Prepared",
                                wasteData?["Total Prepared"]?.toString() ?? "0",
                                Icons.restaurant,
                                Colors.blue,
                              ),
                              analyticsCard(
                                "Total Sold",
                                wasteData?["Total Sold"]?.toString() ?? "0",
                                Icons.shopping_cart,
                                Colors.green,
                              ),
                              analyticsCard(
                                "Total Wasted",
                                wasteData?["Total Wasted"]?.toString() ?? "0",
                                Icons.delete,
                                Colors.red,
                              ),
                              analyticsCard(
                                "Waste %",
                                wasteData?["Waste Percentage"]?.toString() ??
                                    "0%",
                                Icons.percent,
                                Colors.orange,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 30),

                    // 🔷 STUDENT BEHAVIOR SECTION
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Student Behavior",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          GridView.count(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount: 2,
                            crossAxisSpacing: 15,
                            mainAxisSpacing: 15,
                            children: [
                              analyticsCard(
                                "Most Ordered",
                                studentData?["most_popular_food"]?.keys.first ??
                                    "Burger",
                                Icons.fastfood,
                                Colors.purple,
                              ),
                              analyticsCard(
                                "Peak Time",
                                studentData?["peak_order_time"] ?? "1 PM",
                                Icons.schedule,
                                Colors.teal,
                              ),
                              analyticsCard(
                                "Veg Orders",
                                studentData?["veg_preference"] ?? "63%",
                                Icons.eco,
                                Colors.green,
                              ),
                              analyticsCard(
                                "Total Orders",
                                studentData?["total_orders"]?.toString() ??
                                    "200",
                                Icons.receipt_long,
                                Colors.indigo,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
      ),
    );
  }
}
