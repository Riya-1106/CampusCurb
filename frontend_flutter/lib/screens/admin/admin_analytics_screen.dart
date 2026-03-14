import 'package:flutter/material.dart';
import '../../services/prediction_service.dart';

class AdminAnalyticsScreen extends StatefulWidget {
  const AdminAnalyticsScreen({super.key});

  @override
  State<AdminAnalyticsScreen> createState() => _AdminAnalyticsScreenState();
}

class _AdminAnalyticsScreenState extends State<AdminAnalyticsScreen> {
  final PredictionService _service = PredictionService();
  Map<String, dynamic>? data;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    fetchAnalytics();
  }

  Future<void> fetchAnalytics() async {
    try {
      final result = await _service.getStudentAnalytics();
      setState(() {
        data = result;
        loading = false;
      });
    } catch (_) {
      setState(() {
        loading = false;
      });
    }
  }

  Widget dataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(value),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('System Analytics')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : data == null
          ? const Center(child: Text('No analytics data available.'))
          : Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Food Demand Analytics',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          dataRow(
                            'Most Popular Food',
                            data?['most_popular_food']?.keys.first.toString() ??
                                'N/A',
                          ),
                          dataRow(
                            'Peak Order Time',
                            data?['peak_order_time']?.toString() ?? 'N/A',
                          ),
                          dataRow(
                            'Total Orders',
                            data?['total_orders']?.toString() ?? 'N/A',
                          ),
                          dataRow(
                            'Veg Preference',
                            data?['veg_preference']?.toString() ?? 'N/A',
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: fetchAnalytics,
                            child: const Text('Refresh'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
