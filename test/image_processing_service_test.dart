import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:bills_bay_area/core/services/image_processing_service.dart';
import 'package:bills_bay_area/core/services/photo_metadata_service.dart';
import 'package:bills_bay_area/core/services/watermark.dart';

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
      expect(
        decoded.width,
        lessThanOrEqualTo(ImageProcessingService.maxDimension),
      );
      expect(
        decoded.height,
        lessThanOrEqualTo(ImageProcessingService.maxDimension),
      );
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

    test('an unreadable non-JPEG is refused, not uploaded raw', () async {
      // A HEIC-style header neither codec can read. The JPEG strip cannot
      // touch it, so returning it would publish whatever metadata it holds.
      final heicLike = Uint8List.fromList([
        0, 0, 0, 24, ...'ftypheic'.codeUnits, ...List.filled(64, 7),
      ]);
      final noPlatformCodec = ImageProcessingService(
        platformEncoder: (bytes, {required maxDimension, required quality}) async =>
            null,
      );
      await expectLater(
        noPlatformCodec.prepareForUpload(heicLike),
        throwsA(isA<UnsupportedPhotoException>()),
      );
    });
  });

  group('platform encoder tier', () {
    test('its output is scrubbed even if the codec kept the GPS', () async {
      // Stand-in for an OS codec that ignored keepExif: false and passed the
      // original straight through. The upload must still carry no position.
      final original = await fixture('gps_north_west.jpg');
      final leaky = ImageProcessingService(
        platformEncoder:
            (bytes, {required maxDimension, required quality}) async => bytes,
      );

      final prepared = await leaky.prepareForUpload(original);
      expect((await metadata.extract(prepared)).hasLocation, isFalse);
      expect((await metadata.extract(prepared)).isEmpty, isTrue);
    });

    test('is passed the size cap and quality', () async {
      int? seenMax;
      int? seenQuality;
      final spy = ImageProcessingService(
        platformEncoder:
            (bytes, {required maxDimension, required quality}) async {
              seenMax = maxDimension;
              seenQuality = quality;
              return bytes;
            },
      );
      await spy.prepareForUpload(await fixture('no_exif.jpg'));
      expect(seenMax, ImageProcessingService.maxDimension);
      expect(seenQuality, ImageProcessingService.jpegQuality);
    });

    test('a codec that gives up falls back to the Dart encoder', () async {
      final unavailable = ImageProcessingService(
        platformEncoder:
            (bytes, {required maxDimension, required quality}) async => null,
      );
      final wide = img.Image(width: 5000, height: 2500);
      final decoded = img.decodeImage(
        await unavailable.prepareForUpload(
          Uint8List.fromList(img.encodeJpg(wide)),
        ),
      )!;
      expect(decoded.width, ImageProcessingService.maxDimension);
    });

    test('a codec that throws falls back without losing the strip', () async {
      final original = await fixture('gps_north_west.jpg');
      final broken = ImageProcessingService(
        platformEncoder: (bytes, {required maxDimension, required quality}) =>
            throw StateError('codec exploded'),
      );
      final prepared = await broken.prepareForUpload(original);
      expect((await metadata.extract(prepared)).hasLocation, isFalse);
      expect(img.decodeImage(prepared), isNotNull);
    });
  });

  group('watermark', () {
    // A flat grey photo: any stamp shows up as pixels that are no longer grey.
    Uint8List greyPhoto(int w, int h) {
      final photo = img.Image(width: w, height: h)
        ..clear(img.ColorRgb8(128, 128, 128));
      return Uint8List.fromList(img.encodeJpg(photo, quality: 95));
    }

    // Mean distance from flat grey over a region; JPEG noise stays near 0.
    double inkIn(img.Image image, int x0, int y0, int x1, int y1) {
      var total = 0.0;
      var n = 0;
      for (var y = y0; y < y1; y++) {
        for (var x = x0; x < x1; x++) {
          final p = image.getPixel(x, y);
          total += (p.r - 128).abs() + (p.g - 128).abs() + (p.b - 128).abs();
          n++;
        }
      }
      return total / n;
    }

    // Stand-in for the OS codec: resizes and JPEG-encodes anything, PNG
    // included, the way the real one does.
    Future<Uint8List?> fakeCodec(
      Uint8List bytes, {
      required int maxDimension,
      required int quality,
    }) async {
      var image = img.decodeImage(bytes)!;
      final longest = image.width > image.height ? image.width : image.height;
      if (longest > maxDimension) {
        image = image.width >= image.height
            ? img.copyResize(image, width: maxDimension)
            : img.copyResize(image, height: maxDimension);
      }
      return Uint8List.fromList(img.encodeJpg(image, quality: quality));
    }

    test('text is the name with a copyright sign, or nothing', () {
      expect(watermarkText('Bill Kapsalis'), '© Bill Kapsalis');
      expect(watermarkText('  billpics234 '), '© billpics234');
      expect(watermarkText('   '), isNull);
    });

    test('platform path stamps the bottom-right corner only', () async {
      final service = ImageProcessingService(platformEncoder: fakeCodec);
      final out = img.decodeJpg(
        await service.prepareForUpload(
          greyPhoto(1200, 900),
          photographer: 'Bill Kapsalis',
        ),
      )!;
      expect(out.width, 1200);
      expect(inkIn(out, 600, 780, 1200, 900), greaterThan(3)); // the stamp
      expect(inkIn(out, 0, 0, 400, 300), lessThan(2)); // untouched
    });

    test('no photographer, no stamp', () async {
      final service = ImageProcessingService(platformEncoder: fakeCodec);
      final out = img.decodeJpg(
        await service.prepareForUpload(greyPhoto(1200, 900)),
      )!;
      expect(inkIn(out, 600, 780, 1200, 900), lessThan(2));
    });

    test('the Dart fallback stamps too', () async {
      final noCodec = ImageProcessingService(
        platformEncoder: (b, {required maxDimension, required quality}) async =>
            null,
      );
      final out = img.decodeJpg(
        await noCodec.prepareForUpload(
          greyPhoto(1200, 900),
          photographer: 'billpics234',
        ),
      )!;
      expect(inkIn(out, 600, 780, 1200, 900), greaterThan(3));
      expect(inkIn(out, 0, 0, 400, 300), lessThan(2));
    });

    test('a stamp that comes back as a non-JPEG is not uploaded as one', () async {
      // A codec that sizes the photo but hands the stamped PNG back as is.
      var calls = 0;
      final service = ImageProcessingService(
        platformEncoder: (b, {required maxDimension, required quality}) async {
          calls++;
          return calls == 1
              ? fakeCodec(b, maxDimension: maxDimension, quality: quality)
              : b;
        },
      );
      final out = await service.prepareForUpload(
        greyPhoto(800, 600),
        photographer: 'Bill',
      );
      expect(out.sublist(0, 2), [0xFF, 0xD8]); // fell back to a real JPEG
    });

    test('stamping keeps the GPS out', () async {
      final service = ImageProcessingService(platformEncoder: fakeCodec);
      final out = await service.prepareForUpload(
        await fixture('gps_north_west.jpg'),
        photographer: 'Bill',
      );
      expect((await metadata.extract(out)).hasLocation, isFalse);
    });
  });
}
