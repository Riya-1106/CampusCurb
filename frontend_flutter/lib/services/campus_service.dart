import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class CampusService {
  static String get baseUrl {
    if (kIsWeb) return 'http://localhost:8000';
    return 'http://10.0.2.2:8000';
  }

  Future<List<Map<String, dynamic>>> getMenu() async {
    final res = await http.get(Uri.parse('$baseUrl/menu'));
    if (res.statusCode != 200) {
      throw Exception('Could not load menu');
    }
    final list = json.decode(res.body) as List<dynamic>;
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> placeOrder({
    required String uid,
    required String item,
    required int price,
    required int quantity,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/order'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'uid': uid,
        'item': item,
        'price': price,
        'quantity': quantity,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('Order failed: ${res.body}');
    }
  }

  Future<void> addMenuItem({required String name, required int price}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/menu'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'name': name, 'price': price}),
    );
    if (res.statusCode != 200) {
      throw Exception('Add menu failed: ${res.body}');
    }
  }

  Future<void> markAttendance({
    required String uid,
    required String date,
    required String time,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/attendance'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'uid': uid, 'date': date, 'time': time}),
    );
    if (res.statusCode != 200) {
      throw Exception('Attendance failed: ${res.body}');
    }
  }
}
