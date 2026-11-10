import 'package:bills_bay_area/core/services/image_processing_service.dart';
import 'package:bills_bay_area/core/services/photo_metadata_service.dart';
import 'package:bills_bay_area/core/services/platform_image_encoder.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'exif_fixture.dart';
import 'save_sample.dart';

/// Exercises the REAL platform codec, which ordinary unit tests cannot reach:
/// under `flutter test` on the VM it is unavailable and only the Dart
/// fallback runs. Shared by the on-device and in-browser entry points:
///
///   flutter test integration_test -d ANDROID_DEVICE_ID --flavor dev
///   flutter test integration_test -d IOS_SIMULATOR_ID --flavor dev
///   flutter test test/platform_image_encoder_browser_test.dart --platform chrome
void defineEncoderCheck() {
  const metadata = PhotoMetadataService();

  testWidgets('platform codec: used, capped, upright, and no GPS out', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final original = portraitPhotoWithGps();
      // Premise: the input really does carry a location.
      expect((await metadata.extract(original)).hasLocation, isTrue);

      final sw = Stopwatch()..start();
      final native = await encodeWithPlatformCodec(
        original,
        maxDimension: ImageProcessingService.maxDimension,
        quality: ImageProcessingService.jpegQuality,
      );
      final nativeMs = sw.elapsedMilliseconds;

      // Null would mean the fallback ran and nothing here was tested.
      expect(native, isNotNull, reason: 'platform codec did not run');
      // Before the safety scrub: the codec itself should already drop GPS.
      expect((await metadata.extract(native!)).hasLocation, isFalse);

      final out = img.decodeJpg(native)!;
      // Stored 4000x3000 + rotate 90 => upright portrait, long edge capped.
      expect(out.height, greaterThan(out.width), reason: 'not rotated');
      const cap = ImageProcessingService.maxDimension;
      expect(out.height, inInclusiveRange(cap - 8, cap));
      expect(out.width, closeTo(cap * 3 / 4, 8));

      // And through the service, as uploads go.
      final prepared = await const ImageProcessingService().prepareForUpload(
        original,
      );
      expect((await metadata.extract(prepared)).hasLocation, isFalse);
      expect((await metadata.extract(prepared)).isEmpty, isTrue);

      // With the photographer's credit stamped on through the real codec.
      sw.reset();
      final stamped = await const ImageProcessingService().prepareForUpload(
        original,
        photographer: 'Bill Kapsalis',
      );
      final stampMs = sw.elapsedMilliseconds;
      expect(stamped.sublist(0, 2), [0xFF, 0xD8]);
      expect((await metadata.extract(stamped)).hasLocation, isFalse);
      final a = img.decodeJpg(prepared)!, b = img.decodeJpg(stamped)!;
      expect([b.width, b.height], [a.width, a.height]);
      // The stamp changes the bottom-right corner and leaves the rest.
      double diff(int x0, int y0, int x1, int y1) {
        var t = 0.0, n = 0;
        for (var y = y0; y < y1; y += 2) {
          for (var x = x0; x < x1; x += 2) {
            final p = a.getPixel(x, y), q = b.getPixel(x, y);
            t += (p.r - q.r).abs() + (p.g - q.g).abs() + (p.b - q.b).abs();
            n++;
          }
        }
        return t / n;
      }

      final corner = diff(
        b.width ~/ 2,
        b.height - b.height ~/ 12,
        b.width,
        b.height,
      );
      final elsewhere = diff(0, 0, b.width ~/ 2, b.height ~/ 3);
      expect(corner, greaterThan(elsewhere + 3), reason: 'no visible stamp');
      final saved = saveSample('stamped_sample.jpg', stamped);

      // The old path, for comparison.
      sw.reset();
      final dart = await ImageProcessingService(
        platformEncoder: (b, {required maxDimension, required quality}) async =>
            null,
      ).prepareForUpload(original);
      final dartMs = sw.elapsedMilliseconds;

      debugPrint(
        '[encoder-check] ${defaultTargetPlatform.name}${kIsWeb ? ' (web)' : ''}: '
        'in ${original.length ~/ 1024}KB -> '
        'platform ${native.length ~/ 1024}KB in ${nativeMs}ms '
        '(${out.width}x${out.height}); '
        'dart ${dart.length ~/ 1024}KB in ${dartMs}ms; '
        'stamped ${stamped.length ~/ 1024}KB in ${stampMs}ms '
        '(corner diff ${corner.toStringAsFixed(1)} vs '
        '${elsewhere.toStringAsFixed(1)}) saved=$saved',
      );
    });
  });
}
