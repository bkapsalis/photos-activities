import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// Web: the browser's own decoder and JPEG encoder.
///
/// createImageBitmap decodes off the main thread and convertToBlob encodes
/// off it, which is the point: the Dart encoder blocks the page for every
/// photo in a batch. A canvas never writes EXIF into what it encodes.
Future<Uint8List?> encodeWithPlatformCodec(
  Uint8List bytes, {
  required int maxDimension,
  required int quality,
}) async {
  try {
    final blob = web.Blob([bytes.toJS].toJS);
    // from-image applies the EXIF rotation, so width and height below are
    // the upright dimensions and the pixels drawn are already turned.
    final bitmap = await web.window
        .createImageBitmap(
          blob,
          web.ImageBitmapOptions(imageOrientation: 'from-image'),
        )
        .toDart;

    final longest = bitmap.width > bitmap.height ? bitmap.width : bitmap.height;
    final scale = longest > maxDimension ? maxDimension / longest : 1.0;
    final width = (bitmap.width * scale).round().clamp(1, maxDimension);
    final height = (bitmap.height * scale).round().clamp(1, maxDimension);

    final canvas = web.OffscreenCanvas(width, height);
    final ctx =
        canvas.getContext('2d')! as web.OffscreenCanvasRenderingContext2D;
    ctx.imageSmoothingQuality = 'high';
    // JPEG has no alpha; without a fill, transparent PNG areas turn black.
    ctx.fillStyle = '#ffffff'.toJS;
    ctx.fillRect(0, 0, width, height);
    ctx.drawImage(bitmap, 0, 0, width, height);
    bitmap.close();

    final out = await canvas
        .convertToBlob(
          web.ImageEncodeOptions(type: 'image/jpeg', quality: quality / 100),
        )
        .toDart;
    final buffer = await out.arrayBuffer().toDart;
    final encoded = buffer.toDart.asUint8List();
    return encoded.isEmpty ? null : encoded;
  } catch (e) {
    // Older Safari has no OffscreenCanvas, and browsers other than Safari
    // cannot decode HEIC. The Dart encoder gets its turn.
    debugPrint('[image] browser encode failed, using Dart encoder: $e');
    return null;
  }
}
