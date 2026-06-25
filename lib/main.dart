import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/rendering.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    MediaKit.ensureInitialized();
  }

  // ── Suppress RenderFlex overflow yellow/black stripes globally ──
  // When the window is freely resized to any size (very small, thin rectangle,
  // etc.) Flutter's debug renderer paints yellow/black overflow stripes AND
  // throws an error. Intercepting the error prevents both the console spam
  // and the visual stripe painting. Real errors are still printed.
  final originalOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    final String summary = details.exceptionAsString();
    // Silently swallow layout overflow errors — the ClipRect/clipBehavior
    // wrappers in the widget tree already hide the overflowed pixels.
    if (summary.contains('A RenderFlex overflowed') ||
        summary.contains('RenderBox was not laid out') ||
        summary.contains('overflowed by')) {
      // Optionally log to console in debug mode only:
      debugPrint('[Layout] ${summary.split("\n").first}');
      return;
    }
    // Forward all other errors to the original handler.
    originalOnError?.call(details);
  };

  final prefs = await SharedPreferences.getInstance();
  final bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

  runApp(MyApp(isLoggedIn: isLoggedIn));
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;
  const MyApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        primaryColor: const Color(0xFF0F172A), // Deep Navy
        scaffoldBackgroundColor: const Color(0xFFF8FAFC), // Slate 50
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B82F6), // Azure Blue
          primary: const Color(0xFF0F172A),
          secondary: const Color(0xFF3B82F6),
          surface: Colors.white,
        ),
        fontFamily:
            'Inter', // Modern sans-serif (will fallback to Roboto if not found)
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.bold,
          ),
          titleLarge: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w600,
          ),
          bodyMedium: TextStyle(color: Color(0xFF334155)), // Slate 700
          bodySmall: TextStyle(color: Color(0xFF64748B)), // Slate 500
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0F172A),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE2E8F0)), // Slate 200
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF1F5F9), // Slate 100
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
        dataTableTheme: DataTableThemeData(
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
          headingTextStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
            fontSize: 13,
          ),
          dataTextStyle: const TextStyle(
            color: Color(0xFF334155),
            fontSize: 12,
          ),
          dividerThickness: 1,
        ),
      ),
      home: const LoginPage(), // Changed to always show login page as requested
    );
  }
}
