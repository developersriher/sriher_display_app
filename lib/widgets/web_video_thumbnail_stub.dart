import 'package:flutter/material.dart';

// Stub for non-web platforms (Linux, Android, Windows).
// On these platforms, native video thumbnail generation would require
// a separate plugin (e.g. video_thumbnail). For now, returns a placeholder.
Widget buildWebVideoThumbnail({required String url, required BoxFit fit}) {
  return Container(
    color: const Color(0xFF1E293B),
    child: const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.play_circle_fill_rounded, size: 28, color: Color(0xFF94A3B8)),
        SizedBox(height: 2),
        Text(
          'VIDEO',
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.bold,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    ),
  );
}
