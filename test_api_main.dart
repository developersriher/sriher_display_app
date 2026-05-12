import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final url = 'https://display.sriher.com/scheduleMenu_listview';
  final apiKey = '933cdb13cb54e31e694f82bf7f75f0144a9495036db0243b85dd855be53c06f2';
  
  try {
    final response = await http.post(
      Uri.parse(url),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"api_key": apiKey}),
    );
    print("Status: ${response.statusCode}");
    final data = jsonDecode(response.body);
    print("Keys: ${data.keys.toList()}");
    if (data['data'] != null) {
      print("Data count: ${data['data'].length}");
      if (data['data'].isNotEmpty) {
        print("First item: ${data['data'][0]}");
      }
    }
  } catch (e) {
    print("Error: $e");
  }
}
