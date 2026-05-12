import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = "https://display.sriher.com";
  final apiKey = "933cdb13cb54e31e694f82bf7f75f0144a9495036db0243b85dd855be53c06f2";
  
  try {
    final response = await http.post(
      Uri.parse('$baseUrl/schedulerange_scheduleNamesview'),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "api_key": apiKey,
        "schedule_name": "TEST_INSERT_NAME_123"
      }),
    );
    print("STATUS: ${response.statusCode}");
    print("BODY: ${response.body}");
  } catch(e) {}
}
