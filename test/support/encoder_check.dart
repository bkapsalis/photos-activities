import 'package:bills_bay_area/core/services/image_processing_service.dart';
import 'package:bills_bay_area/core/services/photo_metadata_service.dart';
import 'package:bills_bay_area/core/services/platform_image_encoder.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'exif_fixture.dart';

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
      expect(out.height, inInclusiveRange(2040, 2048));
      expect(out.width, inInclusiveRange(1530, 1536));

      // And through the service, as uploads go.
      final prepared = await const ImageProcessingService().prepareForUpload(
        original,
      );
      expect((await metadata.extract(prepared)).hasLocation, isFalse);
      expect((await metadata.extract(prepared)).isEmpty, isTrue);

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
        'dart ${dart.length ~/ 1024}KB in ${dartMs}ms',
      );
    });
  });
}
