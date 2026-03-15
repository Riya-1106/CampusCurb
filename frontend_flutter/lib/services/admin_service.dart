import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';

class AdminService {
  static String get _baseUrl => ApiConfig.baseUrl;

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

  Future<Map<String, dynamic>> getExchangeRequests() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in as admin.');
    }
    final idToken = await currentUser.getIdToken(true);

    final response = await http.get(
      Uri.parse('$_baseUrl/admin/exchange-requests'),
      headers: {'Authorization': 'Bearer $idToken'},
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to load exchange requests');
    }
    return Map<String, dynamic>.from(json.decode(response.body));
  }

  Future<void> updateExchangeStatus(String id, String status) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in as admin.');
    }
    final idToken = await currentUser.getIdToken(true);

    final response = await http.post(
      Uri.parse('$_baseUrl/admin/exchange-status'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: json.encode({'id': id, 'status': status}),
    );
    if (response.statusCode != 200) {
      throw Exception('Update status failed: ${response.body}');
    }
  }

  Future<void> createManagedUser({
    required String email,
    required String password,
    required String role,
    String name = '',
    String department = '',
    String collegeName = '',
    List<String> collegeDomains = const [],
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in as admin.');
    }
    final idToken = await currentUser.getIdToken(true);

    final response = await http.post(
      Uri.parse('$_baseUrl/admin/create-user'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: json.encode({
        'email': email,
        'password': password,
        'role': role,
        'name': name,
        'department': department,
        'college_name': collegeName,
        'college_domains': collegeDomains,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Create account failed: ${response.body}');
    }
  }

  Future<List<Map<String, dynamic>>> getLoginAttempts() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in as admin.');
    }
    final idToken = await currentUser.getIdToken(true);

    final response = await http.get(
      Uri.parse('$_baseUrl/admin/login-attempts'),
      headers: {'Authorization': 'Bearer $idToken'},
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load login attempts: ${response.body}');
    }
    final data = json.decode(response.body) as List<dynamic>;
    return data.map((e) => Map<String, dynamic>.from(e)).toList();
  }
}
