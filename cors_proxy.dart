// CORS Proxy Server for Flutter Web Development
// Run this BEFORE launching `flutter run -d chrome`
// Usage: dart run cors_proxy.dart
//
// This proxy listens on http://localhost:8888 and forwards
// all requests to https://display.sriher.com, adding the
// necessary CORS headers so Chrome allows the requests.

import 'dart:io';
import 'dart:convert';

const int proxyPort = 8888;
const String targetHost = 'display.sriher.com';

void main() async {
  final server = await HttpServer.bind(InternetAddress.anyIPv4, proxyPort);
  print('═══════════════════════════════════════════════════');
  print('  CORS Proxy running on http://localhost:$proxyPort');
  print('  Forwarding to https://$targetHost');
  print('═══════════════════════════════════════════════════');
  print('  Now run: flutter run -d chrome');
  print('═══════════════════════════════════════════════════');

  await for (final request in server) {
    // Handle CORS preflight (OPTIONS)
    if (request.method == 'OPTIONS') {
      request.response
        ..statusCode = 200
        ..headers.set('Access-Control-Allow-Origin', '*')
        ..headers.set('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS')
        ..headers.set('Access-Control-Allow-Headers', 'Content-Type, Accept, Authorization')
        ..headers.set('Access-Control-Max-Age', '86400')
        ..close();
      continue;
    }

    try {
      // Read the incoming request body
      final bodyBytes = await request.fold<List<int>>([], (prev, chunk) => prev..addAll(chunk));
      final bodyStr = utf8.decode(bodyBytes);

      // Forward to the real server
      final client = HttpClient();
      final targetUri = Uri.https(targetHost, request.uri.path, request.uri.queryParameters.isEmpty ? null : request.uri.queryParameters);
      
      final proxyRequest = await client.openUrl(request.method, targetUri);

      // Copy headers from original request
      request.headers.forEach((name, values) {
        if (name.toLowerCase() != 'host' && name.toLowerCase() != 'origin' && name.toLowerCase() != 'referer') {
          for (final v in values) {
            proxyRequest.headers.set(name, v);
          }
        }
      });
      proxyRequest.headers.set('Host', targetHost);
      
      // Forward content-type properly for multipart
      if (bodyBytes.isNotEmpty) {
        proxyRequest.contentLength = bodyBytes.length;
        proxyRequest.add(bodyBytes);
      }

      final proxyResponse = await proxyRequest.close();
      final responseBody = await proxyResponse.fold<List<int>>([], (prev, chunk) => prev..addAll(chunk));

      // Send back to the Flutter app with CORS headers
      request.response
        ..statusCode = proxyResponse.statusCode
        ..headers.set('Access-Control-Allow-Origin', '*')
        ..headers.set('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS')
        ..headers.set('Access-Control-Allow-Headers', 'Content-Type, Accept, Authorization')
        ..headers.set('Content-Type', proxyResponse.headers.contentType?.toString() ?? 'application/json');
      
      request.response.add(responseBody);
      await request.response.close();

      print('[${request.method}] ${request.uri.path} → ${proxyResponse.statusCode}');
      client.close();
    } catch (e) {
      print('[ERROR] ${request.uri.path}: $e');
      request.response
        ..statusCode = 502
        ..headers.set('Access-Control-Allow-Origin', '*')
        ..headers.set('Content-Type', 'application/json')
        ..write(jsonEncode({'error': 'Proxy error: $e'}))
        ..close();
    }
  }
}
