import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';

class CampusService {
  static String get baseUrl => ApiConfig.baseUrl;
  static const Duration _attendanceTimeout = Duration(seconds: 6);
  static const Duration _apiTimeout = Duration(milliseconds: 1500);
  static const Duration _orderTimeout = Duration(seconds: 8);
  static const Duration _profileTimeout = Duration(seconds: 4);
  static const String _attendanceIntentKeyPrefix =
      'attendance_intent_next_checkout_';

  int _readInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  String? _normalizeDateKey(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) {
      return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
    }

    final match = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(raw);
    if (match == null) return raw;
    final year = match.group(1)!;
    final month = match.group(2)!.padLeft(2, '0');
    final day = match.group(3)!.padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _extractErrorMessage(http.Response res, String fallback) {
    try {
      final decoded = json.decode(res.body);
      if (decoded is Map<String, dynamic>) {
        return decoded['detail']?.toString() ??
            decoded['message']?.toString() ??
            fallback;
      }
    } catch (_) {
      // Use fallback message below.
    }
    final body = res.body.trim();
    return body.isEmpty ? fallback : body;
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

  String _attendanceStorageKey(String uid) => 'attendance_records_$uid';
  String _cartStorageKey(String uid) => 'student_cart_$uid';
  String _pointsStorageKey(String uid) => 'cached_points_$uid';
  String _attendanceIntentKey(String uid) => '$_attendanceIntentKeyPrefix$uid';

  Future<void> setAttendanceIntent({
    required String uid,
    required String date,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_attendanceIntentKey(uid), date);
  }

  Future<String?> getAttendanceIntent({required String uid}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_attendanceIntentKey(uid));
    if (raw == null || raw.trim().isEmpty) return null;
    return _normalizeDateKey(raw);
  }

  Future<void> clearAttendanceIntent({required String uid}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_attendanceIntentKey(uid));
  }

  Future<List<Map<String, dynamic>>> _attendanceFromLocal(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_attendanceStorageKey(uid));
    if (raw == null || raw.trim().isEmpty) {
      return [];
    }

    try {
      final decoded = json.decode(raw) as List<dynamic>;
      final records = decoded.map((item) {
        final record = Map<String, dynamic>.from(item as Map);
        final normalizedDate = _normalizeDateKey(record['date']);
        if (normalizedDate != null) {
          record['date'] = normalizedDate;
        }
        return record;
      }).toList();
      records.sort(
        (a, b) => '${b['date'] ?? ''}T${b['time'] ?? ''}'.compareTo(
          '${a['date'] ?? ''}T${a['time'] ?? ''}',
        ),
      );
      return records;
    } catch (_) {
      return [];
    }
  }

  Future<void> _cachePoints(String uid, int points) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_pointsStorageKey(uid), points);
  }

  Future<List<Map<String, dynamic>>> getSavedCart({required String uid}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cartStorageKey(uid));
    if (raw == null || raw.trim().isEmpty) {
      return [];
    }

    try {
      final decoded = json.decode(raw) as List<dynamic>;
      return decoded
          .map((item) {
            final line = Map<String, dynamic>.from(item as Map);
            return <String, dynamic>{
              'key': line['key']?.toString() ?? '',
              'itemName': line['itemName']?.toString() ?? 'Menu item',
              'category': line['category']?.toString() ?? 'general',
              'price': _readInt(line['price']),
              'quantity': _readInt(line['quantity'], fallback: 1).clamp(1, 10),
            };
          })
          .where((line) => (line['key']?.toString().isNotEmpty ?? false))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveCart({
    required String uid,
    required List<Map<String, dynamic>> cart,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cartStorageKey(uid), json.encode(cart));
  }

  Future<void> clearSavedCart({required String uid}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cartStorageKey(uid));
  }

  Future<void> cachePoints({required String uid, required int points}) async {
    await _cachePoints(uid, points);
  }

  Future<int> getCachedPoints({required String uid}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_pointsStorageKey(uid)) ?? 0;
  }

  int _orderPointsFromRecord(Map<String, dynamic> order) {
    final quantity = _readInt(order['quantity'], fallback: 1).clamp(1, 999);
    final category = order['category']?.toString() ?? 'general';
    return (quantity * 10) + _bonusPointsForOrderCategory(category, quantity);
  }

  int _bonusPointsForOrderCategory(String category, int quantity) {
    final normalized = category.trim().toLowerCase();
    if (quantity <= 0) return 0;
    if (normalized == 'meal' || normalized == 'lunch' || normalized == 'rice') {
      return quantity * 6;
    }
    if (normalized == 'breakfast' ||
        normalized == 'snack' ||
        normalized == 'sandwich') {
      return quantity * 4;
    }
    if (normalized == 'dessert' ||
        normalized == 'sweet' ||
        normalized == 'beverage' ||
        normalized == 'drinks') {
      return quantity * 2;
    }
    return quantity * 3;
  }

  int calculateRewardPoints({
    required List<Map<String, dynamic>> orders,
    required List<Map<String, dynamic>> attendanceRecords,
  }) {
    final orderPoints = orders.fold<int>(
      0,
      (runningTotal, order) => runningTotal + _orderPointsFromRecord(order),
    );
    final attendancePoints = attendanceRecords.length * 5;
    return orderPoints + attendancePoints;
  }

  Map<String, dynamic> _attendanceSummary(List<Map<String, dynamic>> records) {
    final now = DateTime.now();
    final todayKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    var monthlyAttendance = 0;
    final normalizedDates = <DateTime>[];

    for (final record in records) {
      final rawDate = _normalizeDateKey(record['date']) ?? '';
      final parsed = DateTime.tryParse(rawDate);
      if (parsed == null) continue;
      normalizedDates.add(parsed);
      if (parsed.year == now.year && parsed.month == now.month) {
        monthlyAttendance += 1;
      }
    }

    normalizedDates.sort((a, b) => b.compareTo(a));
    var streak = 0;
    for (var i = 0; i < normalizedDates.length; i++) {
      final expected = DateTime(now.year, now.month, now.day - i);
      final date = normalizedDates[i];
      if (date.year == expected.year &&
          date.month == expected.month &&
          date.day == expected.day) {
        streak += 1;
      } else {
        break;
      }
    }

    return {
      'has_marked_today': records.any(
        (record) => _normalizeDateKey(record['date']) == todayKey,
      ),
      'current_streak': streak,
      'monthly_attendance': monthlyAttendance,
      'attendance_percentage': records.isEmpty
          ? 0.0
          : ((records.length / 30) * 100).clamp(0, 100),
    };
  }

  Future<int> _currentUserPoints(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final data = doc.data() ?? <String, dynamic>{};
      return _readInt(data['points'] ?? data['rewardPoints']);
    } catch (_) {
      return 0;
    }
  }

  Future<Map<String, dynamic>> _attendanceFromFallback(String uid) async {
    final records = await _attendanceFromLocal(uid);
    return {
      'records': records,
      ..._attendanceSummary(records),
      'is_local_fallback': true,
      'notice':
          'Live attendance could not be reached, so this page is using attendance saved on this device.',
    };
  }

  Future<List<Map<String, dynamic>>> _menuFromFirestore() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('menu')
          .where('approved', isEqualTo: true)
          .get()
          .timeout(_apiTimeout);

      final items = snapshot.docs
          .map((doc) {
            final data = doc.data();
            return <String, dynamic>{
              'id': doc.id,
              'item_id': doc.id,
              'name': data['name']?.toString() ?? '',
              'price': _readInt(data['price']),
              'category': data['category']?.toString() ?? 'general',
              'approved': data['approved'] == true,
            };
          })
          .where(
            (item) => (item['name']?.toString().trim().isNotEmpty ?? false),
          )
          .toList();

      if (items.isNotEmpty) {
        return items;
      }
    } catch (_) {
      // Fall back to lightweight demo menu when Firestore is slow.
    }

    return const [
      {
        'id': 'demo-5',
        'item_id': 'demo-5',
        'name': 'Coffee',
        'price': 66,
        'category': 'beverage',
        'approved': true,
      },
      {
        'id': 'demo-6',
        'item_id': 'demo-6',
        'name': 'Tea',
        'price': 63,
        'category': 'beverage',
        'approved': true,
      },
      {
        'id': 'demo-8',
        'item_id': 'demo-8',
        'name': 'Sandwich',
        'price': 66,
        'category': 'fastfood',
        'approved': true,
      },
      {
        'id': 'demo-9',
        'item_id': 'demo-9',
        'name': 'Noodles',
        'price': 64,
        'category': 'fastfood',
        'approved': true,
      },
      {
        'id': 'demo-10',
        'item_id': 'demo-10',
        'name': 'Burger',
        'price': 68,
        'category': 'fastfood',
        'approved': true,
      },
      {
        'id': 'demo-11',
        'item_id': 'demo-11',
        'name': 'Pasta',
        'price': 67,
        'category': 'fastfood',
        'approved': true,
      },
      {
        'id': 'demo-12',
        'item_id': 'demo-12',
        'name': 'Coke diet',
        'price': 40,
        'category': 'beverage',
        'approved': true,
      },
    ];
  }

  Future<List<Map<String, dynamic>>> _leaderboardFromFirestore() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .get()
          .timeout(_apiTimeout);
      final entries = snapshot.docs.map((doc) {
        final data = doc.data();
        final points = _readInt(data['points'] ?? data['rewardPoints']);
        return <String, dynamic>{
          'uid': doc.id,
          'name': data['name']?.toString().trim().isNotEmpty == true
              ? data['name'].toString().trim()
              : 'Campus User',
          'email': data['email']?.toString() ?? '',
          'role': data['role']?.toString() ?? 'student',
          'points': points,
          'reward': points >= 500
              ? 'Free meal'
              : points >= 250
              ? '10% discount'
              : points >= 100
              ? '5% discount'
              : 'No reward',
        };
      }).toList();

      entries.sort(
        (a, b) => _readInt(b['points']).compareTo(_readInt(a['points'])),
      );
      for (var i = 0; i < entries.length; i++) {
        entries[i]['rank'] = i + 1;
      }
      return entries;
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getMenu() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/menu'))
          .timeout(_apiTimeout);
      if (res.statusCode == 200) {
        final list = json.decode(res.body) as List<dynamic>;
        return list.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } on http.ClientException catch (_) {
      // Fall back to Firestore-approved menu documents below.
    } on TimeoutException catch (_) {
      // Fall back to Firestore-approved menu documents below.
    }
    return _menuFromFirestore();
  }

  Future<List<Map<String, dynamic>>> getOrders({required String uid}) async {
    final res = await http
        .get(Uri.parse('$baseUrl/student/orders/$uid'))
        .timeout(_apiTimeout);
    if (res.statusCode != 200) {
      throw Exception(_extractErrorMessage(res, 'Could not load orders'));
    }
    final list = json.decode(res.body) as List<dynamic>;
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<String, dynamic>> placeOrder({
    required String uid,
    required String item,
    required int price,
    required int quantity,
    String? category,
  }) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/order'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'uid': uid,
            'item': item,
            'price': price,
            'quantity': quantity,
            'category': category,
          }),
        )
        .timeout(_orderTimeout);
    if (res.statusCode != 200) {
      throw Exception(_extractErrorMessage(res, 'Order failed'));
    }
    final payload = json.decode(res.body) as Map<String, dynamic>;
    final totalPoints = _readInt(payload['total_points']);
    await _cachePoints(uid, totalPoints);
    return payload;
  }

  Future<Map<String, dynamic>> placeCartOrder({
    required String uid,
    required List<Map<String, dynamic>> items,
  }) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/order/batch'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'uid': uid, 'items': items}),
        )
        .timeout(_orderTimeout);
    if (res.statusCode != 200) {
      throw Exception(_extractErrorMessage(res, 'Order failed'));
    }
    final payload = json.decode(res.body) as Map<String, dynamic>;
    final totalPoints = _readInt(payload['total_points']);
    await _cachePoints(uid, totalPoints);
    return payload;
  }

  Future<void> addMenuItem({
    required String name,
    required int price,
    String category = 'general',
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/menu'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'name': name, 'price': price, 'category': category}),
    );
    if (res.statusCode != 200) {
      throw Exception(_extractErrorMessage(res, 'Add menu failed'));
    }
  }

  Future<Map<String, dynamic>> markAttendance({
    required String uid,
    required String date,
    required String time,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/attendance'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'uid': uid, 'date': date, 'time': time}),
          )
          .timeout(_attendanceTimeout);
      if (res.statusCode != 200) {
        throw Exception(_extractErrorMessage(res, 'Attendance failed'));
      }
      final payload = json.decode(res.body) as Map<String, dynamic>;
      final totalPoints = _readInt(payload['total_points']);
      await _cachePoints(uid, totalPoints);
      if (payload['intent_saved'] == true) {
        await setAttendanceIntent(uid: uid, date: date);
      }
      return payload;
    } on http.ClientException catch (_) {
      final currentPoints = await _currentUserPoints(uid);
      await setAttendanceIntent(uid: uid, date: date);
      await _cachePoints(uid, currentPoints);
      return {
        'message': 'Attendance intent saved locally',
        'intent_saved': true,
        'attendance_confirmed': false,
        'points_awarded': 0,
        'total_points': currentPoints,
        'is_local_fallback': true,
        'notice':
            'Attendance intent was saved on this device. Checkout will confirm it when the server is reachable.',
      };
    } on TimeoutException catch (_) {
      final currentPoints = await _currentUserPoints(uid);
      await setAttendanceIntent(uid: uid, date: date);
      await _cachePoints(uid, currentPoints);
      return {
        'message': 'Attendance intent saved locally',
        'intent_saved': true,
        'attendance_confirmed': false,
        'points_awarded': 0,
        'total_points': currentPoints,
        'is_local_fallback': true,
        'notice':
            'Attendance intent was saved on this device. Checkout will confirm it when the server is reachable.',
      };
    }
  }

  Future<Map<String, dynamic>> getAttendanceHistory({
    required String uid,
    bool preferLocalOnly = false,
  }) async {
    if (preferLocalOnly) {
      return _attendanceFromFallback(uid);
    }

    try {
      final res = await http
          .get(Uri.parse('$baseUrl/student/attendance/$uid'))
          .timeout(_attendanceTimeout);
      if (res.statusCode != 200) {
        throw Exception(_extractErrorMessage(res, 'Could not load attendance'));
      }
      final payload = json.decode(res.body) as Map<String, dynamic>;
      final liveRecords = (payload['records'] as List<dynamic>? ?? const [])
          .map((item) {
            final record = Map<String, dynamic>.from(item as Map);
            final normalizedDate = _normalizeDateKey(record['date']);
            if (normalizedDate != null) {
              record['date'] = normalizedDate;
            }
            return record;
          })
          .toList();
      final localRecords = await _attendanceFromLocal(uid);
      final mergedByDate = <String, Map<String, dynamic>>{};

      for (final record in liveRecords) {
        final normalizedDate = _normalizeDateKey(record['date']);
        if (normalizedDate == null || normalizedDate.isEmpty) continue;
        record['date'] = normalizedDate;
        mergedByDate[normalizedDate] = record;
      }

      var mergedLocalRecords = false;
      for (final record in localRecords) {
        final normalizedDate = _normalizeDateKey(record['date']);
        if (normalizedDate == null || normalizedDate.isEmpty) continue;
        if (mergedByDate.containsKey(normalizedDate)) continue;
        final normalizedRecord = Map<String, dynamic>.from(record);
        normalizedRecord['date'] = normalizedDate;
        mergedByDate[normalizedDate] = normalizedRecord;
        mergedLocalRecords = true;
      }

      final mergedRecords = mergedByDate.values.toList()
        ..sort(
          (a, b) => '${b['date'] ?? ''}T${b['time'] ?? ''}'.compareTo(
            '${a['date'] ?? ''}T${a['time'] ?? ''}',
          ),
        );
      final mergedSummary = _attendanceSummary(mergedRecords);
      final liveNotice = payload['notice']?.toString();
      final notice = mergedLocalRecords
          ? 'Recent attendance saved on this device has been merged into your timeline.'
          : liveNotice;

      return {
        ...payload,
        ...mergedSummary,
        'records': mergedRecords,
        'is_local_fallback': false,
        if (notice != null && notice.isNotEmpty) 'notice': notice,
      };
    } on http.ClientException catch (_) {
      return _attendanceFromFallback(uid);
    } on TimeoutException catch (_) {
      return _attendanceFromFallback(uid);
    }
  }

  Future<List<Map<String, dynamic>>> getLeaderboard() async {
    if (kIsWeb) {
      return _leaderboardFromFirestore();
    }

    try {
      final res = await http
          .get(Uri.parse('$baseUrl/student/leaderboard'))
          .timeout(_apiTimeout);
      if (res.statusCode == 200) {
        final list = json.decode(res.body) as List<dynamic>;
        return list.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } on http.ClientException catch (_) {
      // Fall back to Firestore ranking if backend is unavailable.
    } on TimeoutException catch (_) {
      // Fall back to Firestore ranking if backend is unavailable.
    }
    return _leaderboardFromFirestore();
  }

  Future<Map<String, dynamic>?> getCurrentProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return null;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get()
          .timeout(_profileTimeout);
      final data = doc.data();
      if (doc.exists && data != null && data.isNotEmpty) {
        return Map<String, dynamic>.from(data);
      }
    } catch (_) {
      // Fall back to backend profile resolution below.
    }

    try {
      final res = await http
          .get(
            Uri.parse('$baseUrl/users/profile'),
            headers: await _authorizedHeaders(),
          )
          .timeout(_profileTimeout);
      if (res.statusCode != 200) {
        return null;
      }
      final decoded = json.decode(res.body);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final profile = decoded['profile'];
      if (profile is! Map) {
        return null;
      }
      return Map<String, dynamic>.from(profile);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> updateProfile({
    required String name,
    required String phone,
    String? department,
    String? collegeName,
    List<String>? collegeDomains,
  }) async {
    final res = await http.put(
      Uri.parse('$baseUrl/users/profile'),
      headers: await _authorizedHeaders(),
      body: json.encode({
        'name': name,
        'phone': phone,
        'department': department,
        'college_name': collegeName,
        'college_domains': collegeDomains,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception(_extractErrorMessage(res, 'Failed to update profile'));
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }
}
