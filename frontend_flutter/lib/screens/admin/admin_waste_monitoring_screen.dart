import 'package:flutter/material.dart';
import '../../services/prediction_service.dart';

class AdminWasteMonitoringScreen extends StatefulWidget {
  const AdminWasteMonitoringScreen({super.key});

  @override
  State<AdminWasteMonitoringScreen> createState() =>
      _AdminWasteMonitoringScreenState();
}

class _AdminWasteMonitoringScreenState
    extends State<AdminWasteMonitoringScreen> {
  final PredictionService _service = PredictionService();
  Map<String, dynamic>? data;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    fetchWasteReport();
  }

  Future<void> fetchWasteReport() async {
    try {
      final result = await _service.getWasteReport();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Waste Monitoring')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : data == null
          ? const Center(child: Text('Could not load waste metrics.'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12),
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
                            'Waste Report',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Total Prepared: ${data!['Total Prepared'] ?? 0}',
                          ),
                          Text('Total Sold: ${data!['Total Sold'] ?? 0}'),
                          Text('Total Wasted: ${data!['Total Wasted'] ?? 0}'),
                          Text(
                            'Waste Percentage: ${data!['Waste Percentage'] ?? '0%'}',
                          ),
                          Text(
                            'Estimated ML Waste Reduction: ${data!['Estimated ML Waste Reduction'] ?? 0}',
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: fetchWasteReport,
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
