import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

final _registeredVideoIds = <String>{};

/// Web implementation: native HTML <video> element with preload="metadata".
/// The browser automatically shows the first frame without needing JS/canvas.
Widget buildWebVideoThumbnail({required String url, required BoxFit fit}) {
  // Unique ID per URL (same pattern as web_compat_image_web.dart)
  final viewId = 'web-vid-thumb-${url.hashCode.abs()}';

  if (!_registeredVideoIds.contains(viewId)) {
    _registeredVideoIds.add(viewId);
    ui_web.platformViewRegistry.registerViewFactory(viewId, (int id) {
      final video = web.document.createElement('video') as web.HTMLVideoElement;
      video.src = url;
      video.preload = 'metadata'; // loads just enough to get the first frame
      video.muted = true;        // required for autoplay policies
      video.currentTime = 0.1;  // seek to 100ms to ensure first frame renders
      video.style.width = '100%';
      video.style.height = '100%';
      video.style.objectFit = _boxFitToCss(fit);
      video.style.display = 'block';
      video.style.backgroundColor = '#1E293B';
      return video;
    });
  }

  return HtmlElementView(viewType: viewId);
}

String _boxFitToCss(BoxFit fit) {
  switch (fit) {
    case BoxFit.cover:
      return 'cover';
    case BoxFit.fill:
      return 'fill';
    case BoxFit.none:
      return 'none';
    case BoxFit.scaleDown:
      return 'scale-down';
    case BoxFit.contain:
    case BoxFit.fitWidth:
    case BoxFit.fitHeight:
      return 'contain';
  }
}
