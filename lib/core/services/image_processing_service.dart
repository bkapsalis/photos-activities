import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'platform_image_encoder.dart';
import 'watermark.dart';

/// Resizes and JPEG-encodes, or returns null if it cannot.
typedef PlatformEncoder =
    Future<Uint8List?> Function(
      Uint8List bytes, {
      required int maxDimension,
      required int quality,
    });

/// Thrown when a photo can be neither re-encoded nor stripped, so uploading
/// it would publish its metadata. The message is shown to the person as is.
class UnsupportedPhotoException implements Exception {
  const UnsupportedPhotoException();

  @override
  String toString() =>
      'This photo could not be processed, so it was not uploaded: its '
      'location data could not be removed. Save it as a JPEG and try again.';
}

/// Prepares picked bytes for upload: smaller, and carrying no metadata.
///
/// Two jobs that have to happen together. The photos in this project run to
/// 16MB because the batch upload sends untouched originals, and those
/// originals carry up to 57KB of EXIF — camera, capture time, and on a phone
/// the GPS position. The file in Storage is world-readable, so the metadata
/// has to come off before it goes up; the Firestore document is the only
/// place location is meant to live.
///
/// Callers must read metadata off the original BEFORE calling this: nothing
/// that comes out of here has any left to read.
///
/// When given a photographer's name, it is also stamped into the picture's
/// bottom-right corner as a visible credit, so a copy taken from the app
/// carries its source with it.
class ImageProcessingService {
  const ImageProcessingService({
    this.platformEncoder = encodeWithPlatformCodec,
  });

  /// Tried first: the OS or browser codec. Injectable so tests can stand in
  /// for a platform that `flutter test` does not have.
  final PlatformEncoder platformEncoder;

  /// Longest edge of the uploaded image. 1600 still fills a phone or the
  /// photo panel on a laptop sharply, while being too small to be worth
  /// lifting for print or resale. (Was 2048.)
  static const maxDimension = 1600;
  static const jpegQuality = 85;

  /// Returns bytes safe to upload: re-encoded, resized, and metadata-free.
  ///
  /// Three tiers, fastest first: the platform codec, then the pure-Dart
  /// encoder, then a byte-wise strip of the original. Every tier's output is
  /// scrubbed of metadata segments, because none of them is trusted to have
  /// dropped it — `image`'s encodeJpg, for one, was verified to write the GPS
  /// straight back out unless the EXIF is cleared first.
  ///
  /// [photographer] is stamped on as "© name". The stamp is a deterrent, not
  /// a privacy measure: if it cannot be drawn by one tier the next is tried,
  /// and only the last resort, a byte-wise strip, goes up unstamped.
  ///
  /// If the image cannot be decoded at all, the original is scrubbed byte-wise
  /// instead of uploaded intact — or, if it is not a JPEG and so cannot be
  /// scrubbed, refused with [UnsupportedPhotoException] — because the one
  /// outcome that must never happen is publishing a file that still has GPS
  /// in it.
  Future<Uint8List> prepareForUpload(
    Uint8List original, {
    String? photographer,
  }) async {
    final stamp = photographer == null ? null : watermarkText(photographer);

    try {
      final native = await platformEncoder(
        original,
        maxDimension: maxDimension,
        quality: jpegQuality,
      );
      if (native != null && native.isNotEmpty) {
        if (stamp == null) return stripMetadataSegments(native);
        final stamped = await _stampAndReencode(native, stamp);
        if (stamped != null) return stripMetadataSegments(stamped);
        debugPrint('[image] stamp failed, using Dart encoder');
      }
    } catch (e) {
      debugPrint('[image] platform encode threw, using Dart encoder: $e');
    }

    try {
      final job = (bytes: original, stamp: stamp);
      final processed = kIsWeb
          // Web has no isolates; the encode blocks the frame, which is why
          // the dimension cap matters more there than the quality setting.
          ? _resizeAndEncode(job)
          : await compute(_resizeAndEncode, job);
      if (processed != null && processed.isNotEmpty) return processed;
    } catch (e) {
      debugPrint('[image] re-encode failed, falling back to strip: $e');
    }

    // The byte-wise strip only understands JPEG; anything else would go up
    // exactly as picked, GPS and all (a HEIC or PNG neither codec could
    // read). Refusing the upload is the only safe answer for those.
    if (!_isJpeg(original)) throw const UnsupportedPhotoException();
    return stripMetadataSegments(original);
  }

  static bool _isJpeg(Uint8List bytes) =>
      bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8;

  /// Draws the stamp on an already sized, upright JPEG, then has the platform
  /// codec turn the PNG that dart:ui produces back into a JPEG. Null if any
  /// step fails, or if what comes back is not a JPEG: the file is stored and
  /// served as image/jpeg, and only a JPEG can be scrubbed.
  Future<Uint8List?> _stampAndReencode(Uint8List jpeg, String stamp) async {
    final png = await stampWithFlutter(jpeg, stamp);
    if (png == null) return null;
    try {
      final out = await platformEncoder(
        png,
        maxDimension: maxDimension,
        quality: jpegQuality,
      );
      return out != null && _isJpeg(out) ? out : null;
    } catch (e) {
      debugPrint('[image] re-encode after stamp failed: $e');
      return null;
    }
  }

  /// Decode, shrink if oversized, stamp, re-encode. Static so it can cross
  /// into an isolate.
  static Uint8List? _resizeAndEncode(({Uint8List bytes, String? stamp}) job) {
    final decoded = img.decodeImage(job.bytes);
    if (decoded == null) return null;

    // bakeOrientation applies the EXIF rotation to the pixels, so the photo
    // still faces the right way once the tag describing that rotation is gone.
    final upright = img.bakeOrientation(decoded);

    // The decoded EXIF rides along on the Image and would be re-emitted by
    // the encoder. Replacing it with an empty container is what actually
    // removes the camera and the GPS from the uploaded file.
    upright.exif = img.ExifData();

    final longest = upright.width > upright.height
        ? upright.width
        : upright.height;
    final sized = longest <= maxDimension
        ? upright
        : img.copyResize(
            upright,
            width: upright.width >= upright.height ? maxDimension : null,
            height: upright.height > upright.width ? maxDimension : null,
            interpolation: img.Interpolation.average,
          );

    // copyResize carries the container across, so clear it on the result too
    // rather than relying on which object the encoder happens to read.
    sized.exif = img.ExifData();

    if (job.stamp != null) stampWithImagePackage(sized, job.stamp!);

    final encoded = img.encodeJpg(sized, quality: jpegQuality);
    // Belt and braces: if a future version of the encoder writes a segment
    // anyway, this removes it. Cheap, and the cost of being wrong is a public
    // file with someone's location in it.
    return stripMetadataSegments(Uint8List.fromList(encoded));
  }

  /// Removes JPEG metadata segments without touching the image data.
  ///
  /// The fallback for a file the decoder will not read. Drops APP1 (EXIF and
  /// XMP), APP2 (ICC/Flashpix), APP13 (IPTC) and COM comments, and leaves
  /// everything the renderer needs. Returns the input unchanged if it is not
  /// a JPEG, since there is nothing here that can be trusted to edit it.
  static Uint8List stripMetadataSegments(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return bytes;

    const dropped = {0xE1, 0xE2, 0xED, 0xFE};
    final out = BytesBuilder()..add([0xFF, 0xD8]);
    var i = 2;

    while (i + 4 <= bytes.length) {
      if (bytes[i] != 0xFF) break;
      final marker = bytes[i + 1];

      // Start of scan, or end of image: the rest is entropy-coded pixel data
      // and must be copied verbatim.
      if (marker == 0xDA || marker == 0xD9) {
        out.add(bytes.sublist(i));
        return out.toBytes();
      }

      final length = (bytes[i + 2] << 8) | bytes[i + 3];
      // A segment claiming to run past the end means the file is damaged;
      // copying the remainder is safer than guessing where it should stop.
      if (length < 2 || i + 2 + length > bytes.length) {
        out.add(bytes.sublist(i));
        return out.toBytes();
      }

      if (!dropped.contains(marker)) {
        out.add(bytes.sublist(i, i + 2 + length));
      }
      i += 2 + length;
    }

    if (i < bytes.length) out.add(bytes.sublist(i));
    return out.toBytes();
  }
}
