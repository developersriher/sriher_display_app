import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// Tracks which view IDs have already been registered to avoid duplicate registration.
final _registeredViewIds = <String>{};

/// Web implementation: registers a native HTML <img> element as a platform view.
/// This bypasses Flutter's Fetch-API-based Image.network which enforces CORS.
/// Browser <img> elements can display cross-origin images without CORS headers.
Widget buildWebImage({required String url, required BoxFit fit}) {
  // Create a unique view ID per URL
  final viewId = 'web-img-${url.hashCode.abs()}';

  // Register the factory only once per unique viewId
  if (!_registeredViewIds.contains(viewId)) {
    _registeredViewIds.add(viewId);
    ui_web.platformViewRegistry.registerViewFactory(viewId, (int id) {
      final img = web.document.createElement('img') as web.HTMLImageElement;
      img.src = url;
      img.style.width = '100%';
      img.style.height = '100%';
      img.style.objectFit = _boxFitToCss(fit);
      img.style.display = 'block';
      return img;
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
