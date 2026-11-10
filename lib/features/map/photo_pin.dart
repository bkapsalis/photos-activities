import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// A photo drawn as a map pin: a small rounded thumbnail in a white frame,
/// which reads clearly against map tiles at pin size.
///
/// Shared by the map tab and the single-photo location page so a photo looks
/// the same wherever it is pinned.
class PhotoPin {
  const PhotoPin._();

  /// Thumbnail pins keyed by image URL, so panning, rebuilding or opening
  /// the same photo again never re-downloads a picture already drawn.
  static final Map<String, BitmapDescriptor> _cache = {};

  /// The pin for the photo at [url]. Falls back to the default red pin if the
  /// picture cannot be loaded, so a photo is never left without a marker.
  ///
  /// This deliberately uses [NetworkImage] rather than a separate HTTP
  /// client: the photo grid already loads these same URLs successfully, so
  /// this reuses a path that is known to work.
  static Future<BitmapDescriptor> iconFor(String url) async {
    final cached = _cache[url];
    if (cached != null) return cached;

    try {
      // Decode at roughly pin size. The full file still downloads, but a
      // 15MB photo is never expanded to full resolution in memory.
      final source = await _resolve(url).timeout(const Duration(seconds: 60));

      const size = 120.0;
      const border = 6.0;
      const inner = size - border * 2;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final rect = const Rect.fromLTWH(0, 0, size, size);

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(18)),
        Paint()..color = Colors.white,
      );
      canvas.save();
      canvas.clipRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(border, border, inner, inner),
          const Radius.circular(12),
        ),
      );
      // Centre-crop rather than squash: photos are rarely square.
      final side = source.width < source.height
          ? source.width.toDouble()
          : source.height.toDouble();
      canvas.drawImageRect(
        source,
        Rect.fromLTWH(
          (source.width - side) / 2,
          (source.height - side) / 2,
          side,
          side,
        ),
        const Rect.fromLTWH(border, border, inner, inner),
        Paint()..filterQuality = FilterQuality.medium,
      );
      canvas.restore();

      final picture = recorder.endRecording();
      final rendered = await picture.toImage(size.round(), size.round());
      final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return BitmapDescriptor.defaultMarker;

      // An explicit logical size keeps the pin the same on every device;
      // without it the plugin scales by the device pixel ratio.
      final icon = BitmapDescriptor.bytes(
        bytes.buffer.asUint8List(),
        width: 56,
        height: 56,
      );
      _cache[url] = icon;
      return icon;
    } catch (e) {
      // A thumbnail that will not load should still leave a usable pin.
      debugPrint('[map] thumbnail failed for $url: $e');
      return BitmapDescriptor.defaultMarker;
    }
  }

  /// Bridges an [ImageProvider]'s listener callbacks into a Future.
  static Future<ui.Image> _resolve(String url) {
    final completer = Completer<ui.Image>();
    final stream = ResizeImage(
      NetworkImage(url),
      width: 240,
      policy: ResizeImagePolicy.fit,
    ).resolve(ImageConfiguration.empty);
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete(info.image);
      },
      onError: (error, stack) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.completeError(error);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }
}
