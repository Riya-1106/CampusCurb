import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AdminService {
  static String get _baseUrl {
    if (kIsWeb) return 'http://localhost:8000';
    return 'http://10.0.2.2:8000';
  }

  Future<List<Map<String, dynamic>>> getMenuPending() async {
    final response = await http.get(Uri.parse('$_baseUrl/admin/menu-pending'));
    if (response.statusCode != 200) {
      throw Exception('Failed to load menu pending');
    }
    final data = json.decode(response.body) as List<dynamic>;
    return data.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> approveMenuItem(String id) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/admin/menu-approve'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'id': id}),
    );
    if (response.statusCode != 200) {
      throw Exception('Approve failed: ${response.body}');
    }
  }

  Future<void> rejectMenuItem(String id) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/admin/menu-reject'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'id': id}),
    );
    if (response.statusCode != 200) {
      throw Exception('Reject failed: ${response.body}');
    }
  }

  Future<List<Map<String, dynamic>>> getExchangeRequests() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/admin/exchange-requests'),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to load exchange requests');
    }
    final data = json.decode(response.body) as List<dynamic>;
    return data.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> updateExchangeStatus(String id, String status) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/admin/exchange-status'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'id': id, 'status': status}),
    );
    if (response.statusCode != 200) {
      throw Exception('Update status failed: ${response.body}');
    }
  }
}
