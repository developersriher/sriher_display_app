import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = "https://display.sriher.com";
  final apiKey = "933cdb13cb54e31e694f82bf7f75f0144a9495036db0243b85dd855be53c06f2";
  
  final endpoints = [
    '/insertSchedule_nameview',
    '/scheduleMenu_insert_nameview',
    '/schedulerange_insertScheduleview',
    '/scheduleName_insertview',
    '/insertScheduleNameview',
    '/schedulerange_insertScheduleNameview'
  ];

  for (var ep in endpoints) {
    try {
      final res = await http.post(Uri.parse('$baseUrl$ep'), body: jsonEncode({
        "api_key": apiKey,
        "schedule_name": "Test12345"
      }), headers: {"Content-Type": "application/json"});
      if (res.statusCode == 200) {
        print('SUCCESS $ep: ${res.statusCode} -> ${res.body}');
      }
    } catch(e) {}
  }
}
