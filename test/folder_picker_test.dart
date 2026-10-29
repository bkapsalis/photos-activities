import 'package:bills_bay_area/core/services/folder_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _folderChannel = MethodChannel('bills_bay_area/folder_picker');
const _locationChannel = MethodChannel('bills_bay_area/media_location');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(_locationChannel, (_) async => true);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_folderChannel, null);
    messenger.setMockMethodCallHandler(_locationChannel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('on Android, reads back the photos of the folder chosen', () async {
    final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF]);
    Object? asked;
    messenger.setMockMethodCallHandler(_folderChannel, (call) async {
      asked = call.arguments;
      return [
        {'name': 'IMG_0001.jpg', 'bytes': jpeg},
      ];
    });

    final images = await pickFolderImages(limit: 7);

    expect(asked, {'limit': 7});
    expect(images.single.name, 'IMG_0001.jpg');
    expect(images.single.bytes, jpeg);
  });

  test('no folder chosen is no photos, not an error', () async {
    messenger.setMockMethodCallHandler(_folderChannel, (_) async => null);
    expect(await pickFolderImages(), isEmpty);
  });

  test('a folder that cannot be read is reported', () async {
    messenger.setMockMethodCallHandler(
      _folderChannel,
      (_) async => throw PlatformException(code: 'folder'),
    );
    expect(pickFolderImages(), throwsA(isA<PlatformException>()));
  });
}
