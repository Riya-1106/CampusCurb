import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';

class CollegeExchangeService {
  static String get _baseUrl => ApiConfig.baseUrl;

  Future<void> submitSignupRequest({
    required String collegeName,
    required String contactName,
    required String email,
    String phone = '',
    String notes = '',
    List<String> allowedDomains = const [],
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/college/signup-request'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'college_name': collegeName,
        'contact_name': contactName,
        'email': email,
        'phone': phone,
        'notes': notes,
        'allowed_domains': allowedDomains,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Signup request failed: ${response.body}');
    }
  }

  Future<String> _token() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('You must be logged in as a college account.');
    }
    final token = await user.getIdToken(true);
    if (token == null || token.isEmpty) {
      throw Exception('Unable to fetch Firebase token.');
    }
    return token;
  }

  Future<List<Map<String, dynamic>>> getMyListings() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/college/listings/mine'),
      headers: {'Authorization': 'Bearer ${await _token()}'},
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to load your listings');
    }
    final data = json.decode(response.body) as List<dynamic>;
    return data.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<List<Map<String, dynamic>>> getAvailableListings() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/college/listings/available'),
      headers: {'Authorization': 'Bearer ${await _token()}'},
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to load available listings');
    }
    final data = json.decode(response.body) as List<dynamic>;
    return data.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<List<Map<String, dynamic>>> getMyRequests() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/college/food-requests'),
      headers: {'Authorization': 'Bearer ${await _token()}'},
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to load food requests');
    }
    final data = json.decode(response.body) as List<dynamic>;
    return data.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> createListing({
    required String foodItem,
    required int quantity,
    required String unit,
    String pickupWindow = '',
    String notes = '',
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/college/listings'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${await _token()}',
      },
      body: json.encode({
        'food_item': foodItem,
        'quantity': quantity,
        'unit': unit,
        'pickup_window': pickupWindow,
        'notes': notes,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to submit listing: ${response.body}');
    }
  }

  Future<void> requestFood({
    required String listingId,
    required int quantity,
    String notes = '',
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/college/food-requests'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${await _token()}',
      },
      body: json.encode({
        'listing_id': listingId,
        'quantity': quantity,
        'notes': notes,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to request food: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> getExchangeRequests(String token) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/admin/exchange-requests'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to load exchange requests: ${response.body}');
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }

  Future<void> updateExchangeStatus(String requestId, String status, String token) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/admin/exchange-status'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode({
        'id': requestId,
        'status': status,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update status: ${response.body}');
    }
  }
}
