import 'package:bills_bay_area/core/services/photo_pickers_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _pickerChannel = MethodChannel('bills_bay_area/photo_picker');
const _locationChannel = MethodChannel('bills_bay_area/media_location');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF]);
  late List<MethodCall> calls;

  void answer(Object? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(_pickerChannel, (call) async {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(() {
    calls = [];
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(_locationChannel, (_) async => true);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_pickerChannel, null);
    messenger.setMockMethodCallHandler(_locationChannel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test("on Android, this device's photos are a folder's, offered "
      'unticked', () async {
    answer(
      (_) => [
        {'id': 'content://folder/IMG_2.jpg', 'name': 'IMG_2.jpg'},
        {'id': 'content://folder/IMG_1.jpg', 'name': 'IMG_1.jpg'},
      ],
    );

    final photos = await pickDevicePhotos(limit: 120);

    expect(calls.single.method, 'pickDeviceFolder');
    expect(calls.single.arguments, {'limit': 120});
    expect(photos.map((p) => p.name), ['IMG_2.jpg', 'IMG_1.jpg']);
    expect(photos.any((p) => p.selected), isFalse);
  });

  test("on Android, the cloud's photos were chosen in Drive, so arrive "
      'ticked', () async {
    answer(
      (_) => [
        {'id': 'content://drive/a', 'name': 'a.jpg'},
        {'id': 'content://drive/b', 'name': 'b.jpg'},
      ],
    );

    final photos = await pickCloudPhotos(limit: 5);

    expect(calls.single.method, 'pickCloudPhotos');
    expect(photos.every((p) => p.selected), isTrue);
  });

  test('on Android, a Drive photo picked by its name opens the picker '
      'again, saying it was added, until the picker is closed', () async {
    final rounds = [
      [
        {'id': 'content://drive/a', 'name': 'a.jpg'},
      ],
      [
        {'id': 'content://drive/b', 'name': 'b.jpg'},
      ],
      null,
    ];
    answer((_) => rounds.removeAt(0));

    final photos = await pickCloudPhotos(limit: 5);

    expect(photos.map((p) => p.name), ['a.jpg', 'b.jpg']);
    expect(calls.map((c) => c.arguments), [
      {'limit': 5},
      {
        'limit': 4,
        'note': '1 photo added. Pick more, or press Back until this closes.',
      },
      {
        'limit': 3,
        'note': '2 photos added. Pick more, or press Back until this closes.',
      },
    ]);
  });

  test('on iOS, the cloud is a folder in Files, offered unticked', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    answer(
      (_) => [
        {'id': 'file:///iCloud/Hikes/a.heic', 'name': 'a.heic'},
      ],
    );

    final photos = await pickCloudPhotos(limit: 5);

    expect(calls.single.method, 'pickCloudFolder');
    expect(photos.single.selected, isFalse);
  });

  test('nothing picked is no photos, not an error', () async {
    answer((_) => null);
    expect(await pickDevicePhotos(limit: 5), isEmpty);
  });

  test('a photo is read in full only when asked, by its id', () async {
    answer((call) => call.method == 'read' ? jpeg : null);
    final photo = nativePhoto(
      id: 'content://folder/IMG_1.jpg',
      name: 'IMG_1.jpg',
      selected: false,
    );
    expect(calls, isEmpty);

    expect(await photo.read(), jpeg);
    expect(calls.single.arguments, {'id': 'content://folder/IMG_1.jpg'});
  });

  test('a photo that cannot be read fails its upload', () async {
    answer((_) => null);
    final photo = nativePhoto(id: 'x', name: 'gone.jpg', selected: true);
    expect(photo.read(), throwsStateError);
  });
}
