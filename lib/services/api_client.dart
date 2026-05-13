import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiClient {
  static const String baseUrl = "https://display.sriher.com";
  
  // Set this to true during web development to bypass CORS issues
  static const bool useProxy = true; 
  static const String proxyUrl = "https://cors-anywhere.herokuapp.com/";

  static String get effectiveBaseUrl => useProxy ? "$proxyUrl$baseUrl" : baseUrl;

  static Map<String, String> get headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  static Future<http.Response> post(String endpoint, Map<String, dynamic> body) async {
    final url = Uri.parse('$effectiveBaseUrl$endpoint');
    return await http.post(
      url,
      headers: headers,
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 15));
  }
}
