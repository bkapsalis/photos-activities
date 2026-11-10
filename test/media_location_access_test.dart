import 'package:bills_bay_area/core/services/media_location_access.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('bills_bay_area/media_location');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void answer(Future<Object?> Function(MethodCall call) handler) =>
      messenger.setMockMethodCallHandler(_channel, handler);

  tearDown(() {
    messenger.setMockMethodCallHandler(_channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  group('on Android', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);

    test('asks the platform for photo-location access', () async {
      final calls = <String>[];
      answer((call) async {
        calls.add(call.method);
        return true;
      });

      expect(await MediaLocationAccess.ensure(), isTrue);
      expect(calls, ['requestMediaLocation']);
    });

    test('a refusal is reported, not thrown', () async {
      answer((_) async => false);
      expect(await MediaLocationAccess.ensure(), isFalse);
    });

    test(
      'rereads a picked photo as the original, by its content address',
      () async {
        final original = Uint8List.fromList([1, 2, 3]);
        Object? askedFor;
        answer((call) async {
          askedFor = call.arguments;
          return original;
        });

        expect(
          await MediaLocationAccess.readOriginal('content://media/image/7'),
          original,
        );
        expect(askedFor, {'uri': 'content://media/image/7'});
      },
    );

    test(
      'when the original cannot be had, says so and lets upload go on',
      () async {
        answer((_) async => throw PlatformException(code: 'denied'));
        expect(await MediaLocationAccess.ensure(), isFalse);
        expect(await MediaLocationAccess.readOriginal('content://x'), isNull);
      },
    );
  });

  group('elsewhere', () {
    test('iOS needs nothing: photos arrive with their location', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      var asked = false;
      answer((_) async {
        asked = true;
        return false;
      });

      expect(await MediaLocationAccess.ensure(), isTrue);
      expect(await MediaLocationAccess.readOriginal('content://x'), isNull);
      expect(asked, isFalse);
    });
  });
}
