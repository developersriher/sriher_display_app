import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = "https://display.sriher.com";
  final apiKey = "933cdb13cb54e31e694f82bf7f75f0144a9495036db0243b85dd855be53c06f2";
  
  try {
    print('Deleting empty templates...');
    final response = await http.post(
      Uri.parse('$baseUrl/new_templateview'),
      body: jsonEncode({"api_key": apiKey}),
      headers: {'Content-Type': 'application/json'},
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final list = data['data'] ?? [];
      for (var t in list) {
        final id = t['id'];
        final name = (t['temp_name'] ?? t['name'] ?? '').toString().trim();
        if (name.isEmpty) {
          final delResp = await http.post(
            Uri.parse('$baseUrl/deleteNew_templateview'),
            body: jsonEncode({"api_key": apiKey, "id": id}),
            headers: {'Content-Type': 'application/json'},
          );
          print('Deleted template $id: ${delResp.statusCode}');
        }
      }
    }
    
    print('Checking categories...');
    final resCat = await http.post(
      Uri.parse('$baseUrl/categoryview'),
      body: jsonEncode({"api_key": apiKey}),
      headers: {'Content-Type': 'application/json'},
    );
    if (resCat.statusCode == 200) {
      final data = jsonDecode(resCat.body);
      final list = data['data'] ?? [];
      for (var c in list) {
        final id = c['id'];
        final name = (c['category_name'] ?? c['name'] ?? '').toString().trim();
        if (name.isEmpty) {
          print('Found empty category with ID: $id');
        } else {
          print('Valid category: $name (ID: $id)');
        }
      }
    }
  } catch (e) {
    print("Error: $e");
  }
}
