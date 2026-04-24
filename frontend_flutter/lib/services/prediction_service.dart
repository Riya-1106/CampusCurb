import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'api_config.dart';

class PredictionService {
  static String get _baseUrl => ApiConfig.baseUrl;
  static const Duration _rewardTimeout = Duration(milliseconds: 1200);
  static const Duration _analyticsTimeout = Duration(seconds: 6);
  static const Duration _operationsTimeout = Duration(seconds: 8);
  static const Duration _trainingTimeout = Duration(seconds: 90);

  static String get backendBaseUrl => _baseUrl;

  String _extractErrorMessage(http.Response response, String fallback) {
    try {
      final decoded = json.decode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded['detail']?.toString() ??
            decoded['message']?.toString() ??
            fallback;
      }
    } catch (_) {
      // Use fallback message below.
    }
    final body = response.body.trim();
    return body.isEmpty ? fallback : body;
  }

  /// Calls the backend /predict endpoint with a payload and returns the response.
  Future<Map<String, dynamic>> predictDemand(Map<String, dynamic> input) async {
    final response = await http
        .post(
          Uri.parse('$_baseUrl/predict'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode(input),
        )
        .timeout(_analyticsTimeout);

    if (response.statusCode != 200) {
      throw Exception('Prediction request failed');
    }

    return json.decode(response.body) as Map<String, dynamic>;
  }

  /// Fetches the demand dashboard data from the backend.
  Future<Map<String, dynamic>> getDemandDashboard({
    String? targetDate,
    String? timeSlot,
  }) async {
    final queryParameters = <String, String>{};
    if (targetDate != null && targetDate.trim().isNotEmpty) {
      queryParameters['target_date'] = targetDate;
    }
    if (timeSlot != null && timeSlot.trim().isNotEmpty) {
      queryParameters['time_slot'] = timeSlot;
    }
    final uri = Uri.parse('$_baseUrl/demand-dashboard').replace(
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
    final response = await http
        .get(uri)
        .timeout(_analyticsTimeout);
    if (response.statusCode != 200) {
      throw Exception('Failed to load demand dashboard');
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getMlOverview() async {
    final response = await http
        .get(Uri.parse('$_baseUrl/ml/overview'))
        .timeout(_analyticsTimeout);
    if (response.statusCode != 200) {
      throw Exception('Failed to load ML overview');
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getMlTrainingStatus() async {
    final response = await http
        .get(Uri.parse('$_baseUrl/ml/training-status'))
        .timeout(_analyticsTimeout);
    if (response.statusCode != 200) {
      throw Exception(_extractErrorMessage(response, 'Failed to load training status'));
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> retrainModel() async {
    final response = await http
        .post(Uri.parse('$_baseUrl/retrain'))
        .timeout(_trainingTimeout);
    if (response.statusCode != 200) {
      throw Exception(_extractErrorMessage(response, 'Failed to retrain model'));
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getCanteenOperations({
    required String date,
    required String timeSlot,
  }) async {
    final uri = Uri.parse('$_baseUrl/canteen/operations').replace(
      queryParameters: {
        'date': date,
        'time_slot': timeSlot,
      },
    );
    final response = await http.get(uri).timeout(_operationsTimeout);
    if (response.statusCode != 200) {
      throw Exception(_extractErrorMessage(response, 'Failed to load canteen operations'));
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> saveCanteenOperations({
    required String date,
    required String timeSlot,
    required List<Map<String, dynamic>> items,
  }) async {
    final response = await http
        .post(
          Uri.parse('$_baseUrl/canteen/operations'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'date': date,
            'time_slot': timeSlot,
            'items': items,
          }),
        )
        .timeout(_operationsTimeout);
    if (response.statusCode != 200) {
      throw Exception(_extractErrorMessage(response, 'Failed to save canteen operations'));
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }

  /// Fetches the waste report from the backend.
  Future<Map<String, dynamic>> getWasteReport() async {
    final response = await http
        .get(Uri.parse('$_baseUrl/waste-report'))
        .timeout(_analyticsTimeout);
    if (response.statusCode != 200) {
      throw Exception('Failed to load waste report');
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }

  /// Fetches the student behavior analytics from the backend.
  Future<Map<String, dynamic>> getStudentAnalytics() async {
    final response = await http
        .get(Uri.parse('$_baseUrl/student-analytics'))
        .timeout(_analyticsTimeout);
    if (response.statusCode != 200) {
      throw Exception('Failed to load student analytics');
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getPredictionAccuracy() async {
    final response = await http
        .get(Uri.parse('$_baseUrl/prediction-accuracy'))
        .timeout(_analyticsTimeout);
    if (response.statusCode != 200) {
      throw Exception('Failed to load prediction accuracy');
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }

  /// Fetches reward description for a given points value.
  Future<String> getReward(int points) async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/rewards/$points'))
          .timeout(_rewardTimeout);
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return data['reward'] as String? ?? _fallbackReward(points);
      }
    } catch (_) {
      // Fall back to local reward thresholds when the backend is unavailable.
    }
    return _fallbackReward(points);
  }

  String _fallbackReward(int points) {
    if (points >= 500) return 'Free meal';
    if (points >= 250) return '10% discount';
    if (points >= 100) return '5% discount';
    return 'No reward';
  }
}
