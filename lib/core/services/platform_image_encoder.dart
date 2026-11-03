/// Resize and JPEG-encode with the platform's own codec rather than pure Dart.
///
/// Android and iOS go through flutter_image_compress (Bitmap / ImageIO), web
/// through the browser's createImageBitmap and canvas encoder. Both are
/// several times faster than the `image` package and keep the work off the
/// UI thread, which on web the Dart path cannot do.
///
/// Returns null when the platform codec is unavailable or fails, so the
/// caller can fall back to the Dart encoder. The result is not trusted to be
/// metadata-free; ImageProcessingService scrubs it either way.
library;

export 'platform_image_encoder_io.dart'
    if (dart.library.js_interop) 'platform_image_encoder_web.dart';
