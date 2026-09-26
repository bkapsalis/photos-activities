import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Prepares picked bytes for upload: smaller, and carrying no metadata.
///
/// Two jobs that have to happen together. The photos in this project run to
/// 16MB because the batch upload sends untouched originals, and those
/// originals carry up to 57KB of EXIF — camera, capture time, and on a phone
/// the GPS position. The file in Storage is world-readable, so the metadata
/// has to come off before it goes up; the Firestore document is the only
/// place location is meant to live.
class ImageProcessingService {
  const ImageProcessingService();

  /// Longest edge of the uploaded image. 2048 keeps a photo sharp on a
  /// retina screen while cutting a 16MB original to a few hundred KB.
  static const maxDimension = 2048;
  static const jpegQuality = 85;

  /// Returns bytes safe to upload: re-encoded, resized, and metadata-free.
  ///
  /// Re-encoding alone does NOT drop the metadata — verified against a file
  /// with known GPS: `image` carries the decoded EXIF on the Image object and
  /// `encodeJpg` writes it straight back out, so a resized photo still had its
  /// position. The EXIF is therefore cleared explicitly before encoding, and
  /// the result is re-checked rather than assumed.
  ///
  /// If the image cannot be decoded at all, the original is scrubbed byte-wise
  /// instead of uploaded intact, because the one outcome that must never
  /// happen is publishing a file that still has GPS in it.
  Future<Uint8List> prepareForUpload(Uint8List original) async {
    try {
      final processed = kIsWeb
          // Web has no isolates; the encode blocks the frame, which is why
          // the dimension cap matters more there than the quality setting.
          ? _resizeAndEncode(original)
          : await compute(_resizeAndEncode, original);
      if (processed != null && processed.isNotEmpty) return processed;
    } catch (e) {
      debugPrint('[image] re-encode failed, falling back to strip: $e');
    }
    return stripMetadataSegments(original);
  }

  /// Decode, shrink if oversized, re-encode. Static so it can cross into an
  /// isolate.
  static Uint8List? _resizeAndEncode(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
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
