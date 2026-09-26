import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:bills_bay_area/core/services/image_processing_service.dart';
import 'package:bills_bay_area/core/services/photo_metadata_service.dart';

Future<Uint8List> fixture(String name) =>
    File('test/fixtures/$name').readAsBytes();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const processing = ImageProcessingService();
  const metadata = PhotoMetadataService();

  group('stripMetadataSegments', () {
    test('removes the GPS that was demonstrably there', () async {
      final original = await fixture('gps_north_west.jpg');
      // Guard the premise: if the fixture ever loses its GPS this test would
      // pass for the wrong reason.
      expect((await metadata.extract(original)).hasLocation, isTrue);

      final stripped = ImageProcessingService.stripMetadataSegments(original);
      expect((await metadata.extract(stripped)).hasLocation, isFalse);
      expect((await metadata.extract(stripped)).isEmpty, isTrue);
    });

    test('leaves the picture itself intact and unchanged in size', () async {
      final original = await fixture('gps_north_west.jpg');
      final before = img.decodeImage(original)!;
      final after = img.decodeImage(
        ImageProcessingService.stripMetadataSegments(original),
      )!;
      expect(after.width, before.width);
      expect(after.height, before.height);
    });

    test('strips the camera identity too, not only location', () async {
      final original = await fixture('exif_no_gps.jpg');
      expect((await metadata.extract(original)).cameraMake, 'Canon');
      final stripped = ImageProcessingService.stripMetadataSegments(original);
      expect((await metadata.extract(stripped)).cameraMake, isNull);
    });

    test('a file with no metadata is left alone', () async {
      final clean = await fixture('no_exif.jpg');
      expect(ImageProcessingService.stripMetadataSegments(clean), clean);
    });

    test('non-JPEG bytes pass through untouched', () {
      final notJpeg = Uint8List.fromList([1, 2, 3, 4, 5, 6]);
      expect(ImageProcessingService.stripMetadataSegments(notJpeg), notJpeg);
      expect(
        ImageProcessingService.stripMetadataSegments(Uint8List(0)),
        isEmpty,
      );
    });

    test('a truncated JPEG does not throw or lose its pixel data', () async {
      final original = await fixture('gps_north_west.jpg');
      final truncated = original.sublist(0, original.length ~/ 2);
      final out = ImageProcessingService.stripMetadataSegments(truncated);
      expect(out.length, lessThanOrEqualTo(truncated.length));
      expect(out.sublist(0, 2), [0xFF, 0xD8]);
    });
  });

  group('prepareForUpload', () {
    test('produces an uploadable file with no location in it', () async {
      final original = await fixture('gps_north_west.jpg');
      expect((await metadata.extract(original)).hasLocation, isTrue);

      final prepared = await processing.prepareForUpload(original);

      // The property that matters: the public file carries no position.
      expect((await metadata.extract(prepared)).hasLocation, isFalse);
      expect((await metadata.extract(prepared)).isEmpty, isTrue);
      // And it is still a usable picture.
      expect(img.decodeImage(prepared), isNotNull);
    });

    test('caps the longest edge', () async {
      // 48px fixture stays as it is; nothing to shrink.
      final small = await fixture('no_exif.jpg');
      final out = await processing.prepareForUpload(small);
      final decoded = img.decodeImage(out)!;
      expect(decoded.width, lessThanOrEqualTo(ImageProcessingService.maxDimension));
      expect(decoded.height, lessThanOrEqualTo(ImageProcessingService.maxDimension));
    });

    test('shrinks an oversized image to the cap', () async {
      final wide = img.Image(width: 5000, height: 2500);
      final bytes = Uint8List.fromList(img.encodeJpg(wide));
      final decoded = img.decodeImage(
        await processing.prepareForUpload(bytes),
      )!;
      expect(decoded.width, ImageProcessingService.maxDimension);
      expect(decoded.height, ImageProcessingService.maxDimension ~/ 2);
    });

    test('undecodable bytes still come back stripped, not raw', () async {
      // The fallback path: whatever happens, GPS must not reach Storage.
      final original = await fixture('gps_north_west.jpg');
      final broken = Uint8List.fromList([
        ...original.sublist(0, 700), // SOI + APP1 with GPS, then garbage
        ...List.filled(40, 0),
      ]);
      expect((await metadata.extract(broken)).hasLocation, isTrue);

      final prepared = await processing.prepareForUpload(broken);
      expect((await metadata.extract(prepared)).hasLocation, isFalse);
    });
  });
}
