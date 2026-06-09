import 'package:flutter/material.dart';

/// Stub implementation for non-web platforms.
/// On Linux/Android/Windows, Image.network works fine (no CORS sandbox).
Widget buildWebImage({required String url, required BoxFit fit}) {
  return Image.network(
    url,
    fit: fit,
    loadingBuilder: (context, child, loadingProgress) {
      if (loadingProgress == null) return child;
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
      );
    },
    errorBuilder: (context, error, stackTrace) => Container(
      color: Colors.black54,
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.broken_image_rounded, color: Colors.white38, size: 40),
          SizedBox(height: 8),
          Text(
            'Image unavailable',
            style: TextStyle(color: Colors.white38, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
