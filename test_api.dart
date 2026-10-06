import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = 'https://display.sriher.com';
  final url = '$baseUrl/schedulerange_scheduleNamesview';
  final apiKey =
      '933cdb13cb54e31e694f82bf7f75f0144a9495036db0243b85dd855be53c06f2';

  try {
    final response = await http.post(
      Uri.parse(url),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"api_key": apiKey}),
    );
    print("Status: ${response.statusCode}");
    print("Body: ${response.body}");
  } catch (e) {
    print("Error: $e");
  }
}
