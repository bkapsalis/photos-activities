import 'package:bills_bay_area/core/services/picked_image.dart';
import 'package:bills_bay_area/core/utils/upload_sources.dart';
import 'package:bills_bay_area/features/home/widgets/upload_images_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  group('describeUploadSource', () {
    String subtitle(
      UploadSource source, {
      required bool isWeb,
      required TargetPlatform p,
    }) => describeUploadSource(source, isWeb: isWeb, platform: p).subtitle;

    test('says where "this device" leads on each platform', () {
      expect(
        subtitle(UploadSource.device, isWeb: false, p: TargetPlatform.android),
        'Folders on this phone',
      );
      expect(
        subtitle(UploadSource.device, isWeb: false, p: TargetPlatform.iOS),
        'Your Photos library',
      );
      // The web on an iPhone reports iOS; it is still a browser.
      expect(
        subtitle(UploadSource.device, isWeb: true, p: TargetPlatform.iOS),
        'Folders on this computer',
      );
    });

    test('names the cloud each platform reaches', () {
      expect(
        subtitle(UploadSource.cloud, isWeb: false, p: TargetPlatform.android),
        'Google Drive',
      );
      expect(
        subtitle(UploadSource.cloud, isWeb: false, p: TargetPlatform.iOS),
        'iCloud Drive',
      );
      expect(
        subtitle(UploadSource.cloud, isWeb: true, p: TargetPlatform.macOS),
        'Google Drive',
      );
    });
  });

  group('UploadSourceList', () {
    testWidgets('lists each source and reports the one tapped', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      UploadSource? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UploadSourceList(
              sources: const [UploadSource.device, UploadSource.cloud],
              onPick: (source) => picked = source,
            ),
          ),
        ),
      );

      expect(find.text('Photos on this device'), findsOneWidget);
      expect(find.text('Your Photos library'), findsOneWidget);
      await tester.tap(find.text('Photos from the Cloud'));
      expect(picked, UploadSource.cloud);
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
          PickedImage.bytes(
            name: 'photo$i.jpg',
            bytes: png,
            selected: selected,
          ),
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
