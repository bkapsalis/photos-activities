import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:bills_bay_area/core/models/photo_metadata.dart';
import 'package:bills_bay_area/core/services/photo_metadata_service.dart';

/// Real JPEGs, not hand-built maps, so these exercise the actual byte parsing.
Future<PhotoMetadata> read(String fixture) async {
  final bytes = await File('test/fixtures/$fixture').readAsBytes();
  return const PhotoMetadataService().extract(bytes);
}

void main() {
  group('PhotoMetadataService', () {
    test('reads a northern/western coordinate', () async {
      final m = await read('gps_north_west.jpg');
      expect(m.hasLocation, isTrue);
      expect(m.latitude, closeTo(37.469924, 0.0001));
      expect(m.longitude, closeTo(-122.311352, 0.0001));
      expect(m.locationSource, LocationSource.exif);
    });

    test('signs a southern/eastern coordinate correctly', () async {
      // Sydney. Getting the hemisphere wrong lands this off Portugal.
      final m = await read('gps_south_east.jpg');
      expect(m.latitude, closeTo(-33.8688, 0.0001));
      expect(m.longitude, closeTo(151.2093, 0.0001));
    });

    test('reads altitude and camera alongside the position', () async {
      final m = await read('gps_north_west.jpg');
      expect(m.altitude, closeTo(92, 0.5));
      expect(m.cameraMake, 'ProbeCam');
      expect(m.cameraModel, 'GPS Fixture 1');
      expect(m.takenAt, DateTime(2026, 9, 26, 10, 30, 0));
    });

    test('a file with EXIF but no GPS yields camera data and no location',
        () async {
      // The dominant real case in this library: a Canon body with no GPS.
      final m = await read('exif_no_gps.jpg');
      expect(m.hasLocation, isFalse);
      expect(m.latitude, isNull);
      expect(m.locationSource, LocationSource.none);
      expect(m.cameraMake, 'Canon');
      expect(m.isEmpty, isFalse);
    });

    test('a file with no EXIF at all returns empty rather than throwing',
        () async {
      final m = await read('no_exif.jpg');
      expect(m.isEmpty, isTrue);
      expect(m.hasLocation, isFalse);
      expect(m.locationSource, LocationSource.none);
    });

    test('zeroed GPS tags are not a location', () async {
      // Byte-for-byte what Android's photo picker returns: every GPS tag
      // present, every value 0/0, hemisphere refs empty. Trusting tag
      // presence here would record Null Island as a real place.
      final m = await read('gps_zeroed_android.jpg');
      expect(m.hasLocation, isFalse);
      expect(m.latitude, isNull);
      expect(m.longitude, isNull);
      expect(m.altitude, isNull);
      expect(m.locationSource, LocationSource.none);
      // The non-GPS half of the same file still survives.
      expect(m.cameraMake, 'ProbeCam');
    });

    test('malformed bytes return empty instead of throwing', () async {
      final full = await File('test/fixtures/gps_north_west.jpg').readAsBytes();
      const service = PhotoMetadataService();
      for (final bytes in [
        full.sublist(0, 20), // header only
        Uint8List.fromList(List.filled(64, 0)), // not an image
        Uint8List(0), // nothing at all
      ]) {
        final m = await service.extract(bytes);
        expect(m.hasLocation, isFalse);
        expect(m.isEmpty, isTrue);
      }
    });

    test('a file truncated after its EXIF still yields that EXIF', () async {
      // EXIF sits in an APP1 segment near the start, so losing the tail of a
      // JPEG does not lose the metadata. Worth pinning down: it is the reason
      // the 256KB range requests used to audit this library worked at all.
      final full = await File('test/fixtures/gps_north_west.jpg').readAsBytes();
      final half = full.sublist(0, full.length ~/ 2);
      final m = await const PhotoMetadataService().extract(half);
      expect(m.hasLocation, isTrue);
      expect(m.latitude, closeTo(37.469924, 0.0001));
    });

    test('fills in dimensions from the decoded image when EXIF lacks them',
        () async {
      final m = await read('no_exif.jpg');
      expect(m.originalWidth, isNull);
      final filled = m.withFallbackSize(48, 32);
      expect(filled.originalWidth, 48);
      expect(filled.originalHeight, 32);
    });

    test('does not overwrite dimensions EXIF already supplied', () async {
      const m = PhotoMetadata(originalWidth: 6000, originalHeight: 4000);
      expect(m.withFallbackSize(48, 32).originalWidth, 6000);
    });
  });

  group('PhotoMetadata privacy helpers', () {
    const precise = PhotoMetadata(
      latitude: 37.4699241,
      longitude: -122.3113516,
      cameraMake: 'Pixel',
      locationSource: LocationSource.exif,
    );

    test('rounding coarsens to about 110m and keeps everything else', () {
      final r = precise.roundedToApproximate();
      expect(r.latitude, 37.47);
      expect(r.longitude, -122.311);
      expect(r.cameraMake, 'Pixel');
      expect(r.hasLocation, isTrue);
    });

    test('rounding a photo with no location is a no-op', () {
      expect(PhotoMetadata.empty.roundedToApproximate().hasLocation, isFalse);
    });

    test('withoutLocation drops the position but keeps the camera', () {
      final w = precise.withoutLocation();
      expect(w.hasLocation, isFalse);
      expect(w.latitude, isNull);
      expect(w.cameraMake, 'Pixel');
      expect(w.locationSource, LocationSource.none);
    });
  });
}
