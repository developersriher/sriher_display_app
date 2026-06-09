import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'web_video_thumbnail_web.dart'
    if (dart.library.io) 'web_video_thumbnail_stub.dart';

/// Displays the first frame of a video as a thumbnail.
///
/// On **web**: renders a native HTML `<video>` element (preload=metadata),
///             which automatically shows the first frame without CORS issues.
/// On **other platforms**: shows a styled play-icon placeholder.
class WebVideoThumbnail extends StatelessWidget {
  final String url;
  final BoxFit fit;

  const WebVideoThumbnail({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return buildWebVideoThumbnail(url: url, fit: fit);
    }
    // Non-web fallback: styled play icon
    return _VideoPlaceholder();
  }
}

class _VideoPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
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
}
