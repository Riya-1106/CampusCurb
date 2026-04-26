import 'dart:convert';

import 'package:http/http.dart' as http;
import 'api_config.dart';

class FacultyService {
  static String get _baseUrl => ApiConfig.baseUrl;
  static const Duration _facultyTimeout = Duration(seconds: 8);

  Future<Map<String, dynamic>> createPayLaterOrder({
    required String facultyId,
    required String itemName,
    required int unitPrice,
    required int quantity,
  }) async {
    final response = await http
        .post(
          Uri.parse('$_baseUrl/faculty/orders'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'faculty_id': facultyId,
            'item_name': itemName,
            'unit_price': unitPrice,
            'quantity': quantity,
          }),
        )
        .timeout(_facultyTimeout);

    if (response.statusCode != 200) {
      throw Exception('Failed to create pay-later order: ${response.body}');
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getPendingSummary({
    required String facultyId,
    String period = 'weekly',
  }) async {
    final response = await http
        .get(
          Uri.parse(
            '$_baseUrl/faculty/pending-summary/$facultyId?period=$period',
          ),
        )
        .timeout(_facultyTimeout);

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch pending summary: ${response.body}');
    }

    return json.decode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getOrders({
    required String facultyId,
    String status = 'pending',
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/faculty/orders/$facultyId',
    ).replace(queryParameters: {'status': status});
    final response = await http.get(uri).timeout(_facultyTimeout);

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch faculty orders: ${response.body}');
    }

    return json.decode(response.body) as Map<String, dynamic>;
  }

  Future<void> settleAllPending({required String facultyId}) async {
    final response = await http
        .post(
          Uri.parse('$_baseUrl/faculty/orders/pay'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'faculty_id': facultyId, 'order_ids': []}),
        )
        .timeout(_facultyTimeout);

    if (response.statusCode != 200) {
      throw Exception('Failed to settle payment: ${response.body}');
    }
  }
}
