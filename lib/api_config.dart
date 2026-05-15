import 'package:flutter/foundation.dart' show kIsWeb;

/// Returns the correct base URL for API calls.
/// On Web (Chrome), routes through the local CORS proxy at localhost:8888.
/// On Desktop (Linux/Mac/Windows), talks directly to the server.
String getBaseUrl() {
  if (kIsWeb) {
    return 'http://localhost:8888';
  }
  return 'https://display.sriher.com';
}
