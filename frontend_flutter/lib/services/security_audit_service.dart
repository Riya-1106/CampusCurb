import 'dart:convert';

import 'package:http/http.dart' as http;
import 'api_config.dart';

class SecurityAuditService {
  static String get _baseUrl => ApiConfig.baseUrl;

  Future<void> logLoginAttempt({
    required String email,
    required String method,
    required bool success,
    required String reason,
    required String selectedRole,
  }) async {
    try {
      await http.post(
        Uri.parse('$_baseUrl/auth/login-attempt'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': email,
          'method': method,
          'success': success,
          'reason': reason,
          'selected_role': selectedRole,
        }),
      );
    } catch (_) {
      // Do not block login UX if audit logging fails.
    }
  }

  Future<void> logAdminAction({
    required String adminId,
    required String action,
    required String targetId,
    required String details,
  }) async {
    try {
      await http.post(
        Uri.parse('$_baseUrl/admin/log-action'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'admin_id': adminId,
          'action': action,
          'target_id': targetId,
          'details': details,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );
    } catch (_) {
      // Do not block admin UX if audit logging fails.
    }
  }
}
