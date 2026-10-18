import 'package:exif_reader/exif_reader.dart';
import 'package:flutter/foundation.dart';

import '../models/photo_metadata.dart';

/// Reads what a photo file says about itself.
///
/// Deliberately free of UI and of Firebase so it can be tested against real
/// files. It never throws: a photo that cannot be parsed is a photo with no
/// metadata, which is an ordinary outcome, not an error worth failing an
/// upload over.
class PhotoMetadataService {
  const PhotoMetadataService();

  /// Extracts metadata from the ORIGINAL bytes.
  ///
  /// Must run before any re-encode. Re-encoding a JPEG rewrites its segments
  /// and drops EXIF, so calling this on compressed output returns nothing.
  Future<PhotoMetadata> extract(Uint8List bytes) async {
    try {
      final exif = await readExifFromBytes(bytes);
      if (exif.tags.isEmpty) {
        debugPrint('[metadata] no EXIF at all');
        return PhotoMetadata.empty;
      }
      final metadata = _fromTags(exif.tags);
      // Says which of three things happened to the location, never the
      // location itself: kept, blanked out by the platform (Android hands
      // over zeroed tags when an app lacks ACCESS_MEDIA_LOCATION), or never
      // recorded by the camera.
      final gpsState = metadata.hasLocation
          ? 'kept'
          : exif.tags.containsKey('GPS GPSLatitude')
          ? 'present but blanked'
          : 'not recorded';
      debugPrint('[metadata] GPS $gpsState');
      return metadata;
    } catch (e) {
      debugPrint('[metadata] unreadable: $e');
      return PhotoMetadata.empty;
    }
  }

  PhotoMetadata _fromTags(Map<String, IfdTag> tags) {
    final lat = _coordinate(tags, 'GPS GPSLatitude', 'GPS GPSLatitudeRef', 'S', 90);
    final lng = _coordinate(tags, 'GPS GPSLongitude', 'GPS GPSLongitudeRef', 'W', 180);

    // Both or neither. Half a coordinate is not a place.
    final hasPair = lat != null && lng != null;
    // Exactly (0, 0) is open ocean off West Africa and is also what a
    // platform-redacted tag set decodes to, so it is read as "no location".
    final usable = hasPair && !(lat == 0 && lng == 0);

    return PhotoMetadata(
      latitude: usable ? lat : null,
      longitude: usable ? lng : null,
      altitude: usable ? _altitude(tags) : null,
      takenAt: _takenAt(tags),
      cameraMake: _text(tags, 'Image Make'),
      cameraModel: _text(tags, 'Image Model'),
      orientation: _int(tags, 'Image Orientation'),
      originalWidth:
          _int(tags, 'EXIF ExifImageWidth') ?? _int(tags, 'Image ImageWidth'),
      originalHeight:
          _int(tags, 'EXIF ExifImageLength') ?? _int(tags, 'Image ImageLength'),
      locationSource: usable ? LocationSource.exif : LocationSource.none,
    );
  }

  /// Degrees from a GPS tag, or null if the value is not a real position.
  ///
  /// Measured on Android: the system photo picker returns the full set of GPS
  /// tags with every value zeroed — `GPSLatitude = [0/0, 0/0, 0/0]` and an
  /// empty hemisphere ref — rather than omitting them. A reader that trusts
  /// tag presence records Null Island as a real place, so each component is
  /// parsed and checked here.
  double? _coordinate(
    Map<String, IfdTag> tags,
    String tag,
    String refTag,
    String negativeRef,
    double limit,
  ) {
    final values = tags[tag]?.values.toList();
    if (values == null || values.length < 3) return null;

    var degrees = 0.0;
    const divisors = [1.0, 60.0, 3600.0];
    for (var i = 0; i < 3; i++) {
      final part = values[i];
      if (part is! Ratio) return null;
      // A zeroed tag arrives as 0/0, which divides to NaN rather than raising.
      if (part.denominator == 0) return null;
      degrees += part.toDouble() / divisors[i];
    }
    if (degrees.isNaN || degrees.isInfinite || degrees > limit) return null;

    // Without a hemisphere the sign is a guess, and a guess puts the pin on
    // the wrong side of the equator or the meridian.
    final ref = tags[refTag]?.printable.trim().toUpperCase() ?? '';
    if (ref.isEmpty) return null;
    return ref == negativeRef ? -degrees : degrees;
  }

  double? _altitude(Map<String, IfdTag> tags) {
    final value = tags['GPS GPSAltitude']?.values.toList().firstOrNull;
    if (value is! Ratio || value.denominator == 0) return null;
    final metres = value.toDouble();
    if (metres.isNaN || metres.isInfinite) return null;
    // Ref 1 means below sea level.
    final below = tags['GPS GPSAltitudeRef']?.values.firstAsInt() == 1;
    return below ? -metres : metres;
  }

  /// EXIF dates look like "2026:09:26 10:30:00" — colons in the date part,
  /// which [DateTime.parse] will not accept.
  DateTime? _takenAt(Map<String, IfdTag> tags) {
    for (final tag in const [
      'EXIF DateTimeOriginal',
      'EXIF DateTimeDigitized',
      'Image DateTime',
    ]) {
      final raw = _text(tags, tag);
      if (raw == null) continue;
      final m = RegExp(
        r'^(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})',
      ).firstMatch(raw);
      if (m == null) continue;
      final parts = [for (var i = 1; i <= 6; i++) int.parse(m.group(i)!)];
      // A camera with a flat clock writes zeroes; DateTime would silently roll
      // that into the previous month.
      if (parts[1] < 1 || parts[1] > 12 || parts[2] < 1 || parts[2] > 31) {
        continue;
      }
      return DateTime(
        parts[0],
        parts[1],
        parts[2],
        parts[3],
        parts[4],
        parts[5],
      );
    }
    return null;
  }

  String? _text(Map<String, IfdTag> tags, String tag) {
    final value = tags[tag]?.printable.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  int? _int(Map<String, IfdTag> tags, String tag) {
    final values = tags[tag]?.values;
    if (values == null || values.length == 0) return null;
    try {
      return values.firstAsInt();
    } catch (_) {
      return null;
    }
  }
}
