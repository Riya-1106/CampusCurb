import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'api_config.dart';

class NotificationService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  static String get _baseUrl => ApiConfig.baseUrl;

  Future<void> initializeForSignedInUser() async {
    try {
      await _firebaseMessaging.requestPermission();
      final token = await _firebaseMessaging.getToken();
      if (token != null) {
        await _registerToken(token);
      }

      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        await _registerToken(newToken);
      });

      onMessage();
    } catch (e) {
      // Web dev may fail to register service worker; keep auth flow functional.
      debugPrint('Skipping notification init: $e');
    }
  }

  void onMessage() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Received message: ${message.notification?.title}');
    });
  }

  Future<void> _registerToken(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final idToken = await user.getIdToken();
    await http.post(
      Uri.parse('$_baseUrl/notifications/register-token'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: json.encode({'token': token}),
    );
  }
}
