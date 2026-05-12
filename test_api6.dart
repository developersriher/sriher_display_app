import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = "https://display.sriher.com";
  final apiKey = "933cdb13cb54e31e694f82bf7f75f0144a9495036db0243b85dd855be53c06f2";
  
  final endpoints = [
    '/schedulerange_insertScheduleNameview',
    '/scheduleName_insertview',
    '/insertScheduleNameview',
    '/schedulerange_insertScheduleview',
    '/scheduleMenu_insertNameview',
  ];

  for(var ep in endpoints) {
      try {
        final res = await http.post(
          Uri.parse('$baseUrl$ep'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "api_key": apiKey,
            "schedule_name": "TEST_AUTO_2024"
          }),
        );
        print("EP: $ep -> ${res.statusCode} ${res.body.length > 100 ? res.body.substring(0, 100) : res.body}");
      } catch(e) {}
  }
}
