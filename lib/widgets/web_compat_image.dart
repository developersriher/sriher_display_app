import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ─── Web-only imports (conditional) ──────────────────────────────────────────
// On web, Flutter's Image.network uses the browser's Fetch API which enforces
// strict CORS. If the server at display.sriher.com doesn't send
// Access-Control-Allow-Origin headers, Chrome blocks the request (statusCode 0).
//
// The fix: on Web, use a native HTML <img> element registered as a platform view.
// Browser <img> tags display cross-origin images without CORS restrictions
// (they just can't be pixel-read by JS canvas, but for display that's fine).
//
// On non-web platforms (Linux, Android, Windows) Image.network works normally
// since there is no browser CORS sandbox.

import 'web_compat_image_web.dart'
    if (dart.library.io) 'web_compat_image_stub.dart';

/// A cross-platform image widget that works around Chrome CORS restrictions.
///
/// On **web**: renders via a native HTML <img> element (no CORS restriction).
/// On **other platforms**: uses standard [Image.network].
class WebCompatImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final Color? color;
  final BlendMode? colorBlendMode;

  const WebCompatImage({
    super.key,
    required this.url,
    this.fit = BoxFit.contain,
    this.color,
    this.colorBlendMode,
  });

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return buildWebImage(url: url, fit: fit);
    }
    return Image.network(
      url,
      fit: fit,
      color: color,
      colorBlendMode: colorBlendMode,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      },
      errorBuilder: (context, error, stackTrace) => _ErrorPlaceholder(url: url),
    );
  }
}

class _ErrorPlaceholder extends StatelessWidget {
  final String url;
  const _ErrorPlaceholder({required this.url});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.broken_image_rounded, color: Colors.white38, size: 40),
          const SizedBox(height: 8),
          Text(
            'Image unavailable',
            style: const TextStyle(color: Colors.white38, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
