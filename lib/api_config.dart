import 'package:flutter/foundation.dart' show kIsWeb;

/// Returns the correct base URL for API calls.
/// Can be overridden at compile time using:
/// flutter run --dart-define=API_BASE_URL=https://your-api.com
String getBaseUrl() {
  const String envBaseUrl = String.fromEnvironment('API_BASE_URL');
  if (envBaseUrl.isNotEmpty) {
    return envBaseUrl;
  }

  // if (kIsWeb) {
  //   return 'http://127.0.0.1/sriherdisplay/public';
  // }
  return 'https://display.sriher.com';
}
