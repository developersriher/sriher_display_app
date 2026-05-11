import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = "https://display.sriher.com";
  final apiKey = "933cdb13cb54e31e694f82bf7f75f0144a9495036db0243b85dd855be53c06f2";
  
  try {
    final response = await http.post(
      Uri.parse('$baseUrl/scheduleMenu_listview'),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"api_key": apiKey}),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final list = data['data'] ?? [];
      
      final seen = <int>{};
      for (var item in list) {
        final id = int.tryParse(item['id']?.toString() ?? '');
        if (id == null) {
          print('NULL ID FOUND: $item');
        } else if (seen.contains(id)) {
          print('DUPLICATE ID FOUND: $id');
        }
        if (id != null) seen.add(id);
      }
    }
  } catch(e) {}
}
