import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';

class PredictionService {
  static String get _baseUrl => ApiConfig.baseUrl;
  static const Duration _rewardTimeout = Duration(milliseconds: 1200);
  static const Duration _analyticsTimeout = Duration(seconds: 12);
  static const Duration _operationsTimeout = Duration(seconds: 8);
  static const Duration _trainingTimeout = Duration(seconds: 90);
  static const String _cachePrefix = 'prediction_cache_';

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

  String _cacheKey(String suffix) => '$_cachePrefix$suffix';

  Future<void> _writeMapCache(String key, Map<String, dynamic> payload) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey(key), json.encode(payload));
  }

  Future<Map<String, dynamic>?> _readMapCache(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey(key));
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = json.decode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      // Ignore corrupt cache and fall through.
    }
    return null;
  }

  Future<Map<String, String>> _authorizedHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User is not signed in');
    }
    final token = await user.getIdToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
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
    final cacheKey =
        'demand_dashboard_${targetDate ?? 'today'}_${timeSlot ?? 'default'}';
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
    try {
      final response = await http.get(uri).timeout(_analyticsTimeout);
      if (response.statusCode != 200) {
        throw Exception('Failed to load demand dashboard');
      }
      final payload = json.decode(response.body) as Map<String, dynamic>;
      await _writeMapCache(cacheKey, payload);
      return payload;
    } catch (error) {
      final cached = await _readMapCache(cacheKey);
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getMlOverview() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/ml/overview'))
          .timeout(_analyticsTimeout);
      if (response.statusCode != 200) {
        throw Exception('Failed to load ML overview');
      }
      final payload = json.decode(response.body) as Map<String, dynamic>;
      await _writeMapCache('ml_overview', payload);
      return payload;
    } catch (error) {
      final cached = await _readMapCache('ml_overview');
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getMlTrainingStatus() async {
    final response = await http
        .get(Uri.parse('$_baseUrl/ml/training-status'))
        .timeout(_analyticsTimeout);
    if (response.statusCode != 200) {
      throw Exception(
        _extractErrorMessage(response, 'Failed to load training status'),
      );
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> retrainModel() async {
    final response = await http
        .post(Uri.parse('$_baseUrl/retrain'))
        .timeout(_trainingTimeout);
    if (response.statusCode != 200) {
      throw Exception(
        _extractErrorMessage(response, 'Failed to retrain model'),
      );
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getCanteenOperations({
    required String date,
    required String timeSlot,
  }) async {
    final cacheKey = 'canteen_operations_${date}_$timeSlot';
    final uri = Uri.parse(
      '$_baseUrl/canteen/operations',
    ).replace(queryParameters: {'date': date, 'time_slot': timeSlot});
    try {
      final response = await http.get(uri).timeout(_operationsTimeout);
      if (response.statusCode != 200) {
        throw Exception(
          _extractErrorMessage(response, 'Failed to load canteen operations'),
        );
      }
      final payload = json.decode(response.body) as Map<String, dynamic>;
      await _writeMapCache(cacheKey, payload);
      return payload;
    } catch (error) {
      final cached = await _readMapCache(cacheKey);
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getCanteenOrderQueue() async {
    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl/canteen/order-queue'),
            headers: await _authorizedHeaders(),
          )
          .timeout(_operationsTimeout);
      if (response.statusCode != 200) {
        throw Exception(
          _extractErrorMessage(response, 'Failed to load canteen order queue'),
        );
      }
      final payload = json.decode(response.body) as Map<String, dynamic>;
      await _writeMapCache('canteen_order_queue', payload);
      return payload;
    } catch (error) {
      final cached = await _readMapCache('canteen_order_queue');
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> updateCanteenOrderQueueStatus({
    required String source,
    required String pickupStatus,
    String? orderToken,
    String? orderId,
  }) async {
    final response = await http
        .post(
          Uri.parse('$_baseUrl/canteen/order-queue/status'),
          headers: await _authorizedHeaders(),
          body: json.encode({
            'source': source,
            'pickup_status': pickupStatus,
            if (orderToken != null && orderToken.trim().isNotEmpty)
              'order_token': orderToken,
            if (orderId != null && orderId.trim().isNotEmpty) 'order_id': orderId,
          }),
        )
        .timeout(_operationsTimeout);
    if (response.statusCode != 200) {
      throw Exception(
        _extractErrorMessage(response, 'Failed to update pickup status'),
      );
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
          headers: await _authorizedHeaders(),
          body: json.encode({
            'date': date,
            'time_slot': timeSlot,
            'items': items,
          }),
        )
        .timeout(_operationsTimeout);
    if (response.statusCode != 200) {
      throw Exception(
        _extractErrorMessage(response, 'Failed to save canteen operations'),
      );
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }

  /// Fetches the waste report from the backend.
  Future<Map<String, dynamic>> getWasteReport() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/waste-report'))
          .timeout(_analyticsTimeout);
      if (response.statusCode != 200) {
        throw Exception('Failed to load waste report');
      }
      final payload = json.decode(response.body) as Map<String, dynamic>;
      await _writeMapCache('waste_report', payload);
      return payload;
    } catch (error) {
      final cached = await _readMapCache('waste_report');
      if (cached != null) return cached;
      rethrow;
    }
  }

  /// Fetches the student behavior analytics from the backend.
  Future<Map<String, dynamic>> getStudentAnalytics() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/student-analytics'))
          .timeout(_analyticsTimeout);
      if (response.statusCode != 200) {
        throw Exception('Failed to load student analytics');
      }
      final payload = json.decode(response.body) as Map<String, dynamic>;
      await _writeMapCache('student_analytics', payload);
      return payload;
    } catch (error) {
      final cached = await _readMapCache('student_analytics');
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getPredictionAccuracy() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/prediction-accuracy'))
          .timeout(_analyticsTimeout);
      if (response.statusCode != 200) {
        throw Exception('Failed to load prediction accuracy');
      }
      final payload = json.decode(response.body) as Map<String, dynamic>;
      await _writeMapCache('prediction_accuracy', payload);
      return payload;
    } catch (error) {
      final cached = await _readMapCache('prediction_accuracy');
      if (cached != null) return cached;
      rethrow;
    }
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
