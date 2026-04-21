import 'package:flutter/foundation.dart';

class ApiConfig {
  static const String _configuredBaseUrl = String.fromEnvironment(
    'BACKEND_BASE_URL',
    defaultValue: '',
  );

  static String get baseUrl {
    final configured = _configuredBaseUrl.trim();
    if (configured.isNotEmpty) {
      return configured.endsWith('/')
          ? configured.substring(0, configured.length - 1)
          : configured;
    }

    if (kIsWeb) {
      final currentBase = Uri.base;
      final host = currentBase.host.isEmpty ? 'localhost' : currentBase.host;
      // On Flutter web, the UI usually runs on a dev-server port while FastAPI
      // serves on 8000. Reuse the current host so phones on the same network
      // still reach the backend on the laptop.
      return '${currentBase.scheme}://$host:8000';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://10.0.2.2:8000';
      default:
        return 'http://localhost:8000';
    }
  }
}
