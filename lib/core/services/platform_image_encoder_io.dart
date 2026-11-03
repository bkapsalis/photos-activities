import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Android and iOS: the OS codec via flutter_image_compress.
Future<Uint8List?> encodeWithPlatformCodec(
  Uint8List bytes, {
  required int maxDimension,
  required int quality,
}) async {
  try {
    final minEdge = await _minEdgeFor(bytes, maxDimension);
    final out = await FlutterImageCompress.compressWithList(
      bytes,
      minWidth: minEdge,
      minHeight: minEdge,
      quality: quality,
      format: CompressFormat.jpeg,
      // Bakes the EXIF rotation into the pixels, as bakeOrientation does on
      // the Dart path, so the photo still faces the right way without it.
      autoCorrectionAngle: true,
      keepExif: false,
    );
    return out.isEmpty ? null : out;
  } catch (e) {
    // MissingPluginException under `flutter test`, or a format the OS will
    // not decode. Either way the Dart encoder gets its turn.
    debugPrint('[image] platform encode failed, using Dart encoder: $e');
    return null;
  }
}

/// The value to pass as both minWidth and minHeight so the LONGEST edge lands
/// on [maxDimension].
///
/// The plugin's size arguments are a floor, not a cap: on both Android and
/// iOS it scales down until the shorter edge reaches them. Passing the cap
/// directly would leave a 4000x3000 photo at 2730x2048. Scaling the shorter
/// edge by maxDimension / longest instead yields the capped size, and since
/// the value is the same for both arguments it holds whether or not the photo
/// is rotated by EXIF.
Future<int> _minEdgeFor(Uint8List bytes, int maxDimension) async {
  try {
    // ImageDescriptor reads the header only, not the pixels.
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final w = descriptor.width;
    final h = descriptor.height;
    descriptor.dispose();
    buffer.dispose();

    final longest = w > h ? w : h;
    final shortest = w > h ? h : w;
    if (longest <= maxDimension) return shortest;
    final edge = shortest * maxDimension ~/ longest;
    return edge < 1 ? 1 : edge;
  } catch (_) {
    // A format Flutter cannot read the header of (the OS codec may still
    // manage, e.g. HEIC). Capping the short edge is the closest safe guess.
    return maxDimension;
  }
}
