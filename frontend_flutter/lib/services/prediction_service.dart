import 'dart:convert';

import 'package:http/http.dart' as http;
import 'api_config.dart';

class PredictionService {
  static String get _baseUrl => ApiConfig.baseUrl;

  static String get backendBaseUrl => _baseUrl;

  /// Calls the backend /predict endpoint with a payload and returns the response.
  Future<Map<String, dynamic>> predictDemand(Map<String, dynamic> input) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/predict'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(input),
    );

    if (response.statusCode != 200) {
      throw Exception('Prediction request failed');
    }

    return json.decode(response.body) as Map<String, dynamic>;
  }

  /// Fetches the demand dashboard data from the backend.
  Future<Map<String, dynamic>> getDemandDashboard() async {
    final response = await http.get(Uri.parse('$_baseUrl/demand-dashboard'));
    if (response.statusCode != 200) {
      throw Exception('Failed to load demand dashboard');
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }

  /// Fetches the waste report from the backend.
  Future<Map<String, dynamic>> getWasteReport() async {
    final response = await http.get(Uri.parse('$_baseUrl/waste-report'));
    if (response.statusCode != 200) {
      throw Exception('Failed to load waste report');
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }

  /// Fetches the student behavior analytics from the backend.
  Future<Map<String, dynamic>> getStudentAnalytics() async {
    final response = await http.get(Uri.parse('$_baseUrl/student-analytics'));
    if (response.statusCode != 200) {
      throw Exception('Failed to load student analytics');
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getPredictionAccuracy() async {
    final response = await http.get(Uri.parse('$_baseUrl/prediction-accuracy'));
    if (response.statusCode != 200) {
      throw Exception('Failed to load prediction accuracy');
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }

  /// Fetches reward description for a given points value.
  Future<String> getReward(int points) async {
    final response = await http.get(Uri.parse('$_baseUrl/rewards/$points'));
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch reward');
    }
    final data = json.decode(response.body) as Map<String, dynamic>;
    return data['reward'] as String? ?? 'No reward';
  }
}
