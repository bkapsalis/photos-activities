import 'package:bills_bay_area/core/utils/upload_sources.dart';
import 'package:bills_bay_area/features/home/widgets/upload_images_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  group('uploadSourcesFor', () {
    test('Android offers its photo library, the file browser and a whole '
        'folder', () {
      expect(uploadSourcesFor(isWeb: false, platform: TargetPlatform.android), [
        UploadSource.photoLibrary,
        UploadSource.files,
        UploadSource.folder,
      ]);
    });

    test('iOS offers its photo library and Files, where Select takes a '
        'folder', () {
      expect(uploadSourcesFor(isWeb: false, platform: TargetPlatform.iOS), [
        UploadSource.photoLibrary,
        UploadSource.files,
      ]);
    });

    test('the web offers its file dialog and a whole folder', () {
      // Web on an iPhone reports iOS; it is still a browser.
      for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
        expect(uploadSourcesFor(isWeb: true, platform: platform), [
          UploadSource.files,
          UploadSource.folder,
        ]);
      }
    });
  });

  group('describeUploadSource', () {
    String filesTitle({required bool isWeb, required TargetPlatform p}) =>
        describeUploadSource(
          UploadSource.files,
          isWeb: isWeb,
          platform: p,
        ).title;

    test('names the drives each platform can reach', () {
      expect(
        filesTitle(isWeb: false, p: TargetPlatform.android),
        'Google Drive & files',
      );
      expect(
        filesTitle(isWeb: false, p: TargetPlatform.iOS),
        'iCloud Drive & files',
      );
      expect(
        filesTitle(isWeb: true, p: TargetPlatform.macOS),
        'Photos & files on this device',
      );
    });
  });

  test('the upload menu names only the drives this platform reaches', () {
    expect(
      uploadSourcesSummary(isWeb: false, platform: TargetPlatform.android),
      isNot(contains('iCloud')),
    );
    expect(
      uploadSourcesSummary(isWeb: false, platform: TargetPlatform.iOS),
      contains('iCloud Drive'),
    );
  });

  group('UploadSourceList', () {
    testWidgets('lists each source and reports the one tapped', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      UploadSource? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UploadSourceList(
              sources: const [UploadSource.photoLibrary, UploadSource.files],
              onPick: (source) => picked = source,
            ),
          ),
        ),
      );

      expect(find.text('Photos on this device'), findsOneWidget);
      await tester.tap(find.text('iCloud Drive & files'));
      expect(picked, UploadSource.files);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('UploadSelectionGrid', () {
    final png = img.encodePng(img.Image(width: 4, height: 4));

    Future<List<PickedImage>> pumpGrid(
      WidgetTester tester, {
      required int count,
      required bool selected,
    }) async {
      final images = [
        for (var i = 0; i < count; i++)
          PickedImage(name: 'photo$i.jpg', bytes: png, selected: selected),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => UploadSelectionGrid(
                images: images,
                onToggle: (image) =>
                    setState(() => image.selected = !image.selected),
                onSelectAll: () => setState(() {
                  for (final image in images) {
                    image.selected = true;
                  }
                }),
                onSelectNone: () => setState(() {
                  for (final image in images) {
                    image.selected = false;
                  }
                }),
              ),
            ),
          ),
        ),
      );
      return images;
    }

    testWidgets('a folder that arrives unticked is taken whole by '
        'Select all', (tester) async {
      final images = await pumpGrid(tester, count: 5, selected: false);
      expect(find.text('0 of 5 selected'), findsOneWidget);
      expect(
        find.text('Tap the photos to upload, or Select all.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Select all'));
      await tester.pump();

      expect(find.text('5 of 5 selected'), findsOneWidget);
      expect(images.every((image) => image.selected), isTrue);
    });

    testWidgets('tapping a photo leaves it out, and tapping again puts it '
        'back', (tester) async {
      final images = await pumpGrid(tester, count: 3, selected: true);

      await tester.tap(find.bySemanticsLabel('photo1.jpg'));
      await tester.pump();
      expect(find.text('2 of 3 selected'), findsOneWidget);
      expect(images[1].selected, isFalse);

      await tester.tap(find.bySemanticsLabel('photo1.jpg'));
      await tester.pump();
      expect(find.text('3 of 3 selected'), findsOneWidget);
    });

    testWidgets('Select none clears every tick', (tester) async {
      final images = await pumpGrid(tester, count: 4, selected: true);

      await tester.tap(find.text('Select none'));
      await tester.pump();

      expect(find.text('0 of 4 selected'), findsOneWidget);
      expect(images.any((image) => image.selected), isFalse);
    });
  });
}
