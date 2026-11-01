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

    test('tells a computer\'s browser and the Android app how to pick '
        'several Drive photos', () {
      String? note(
        UploadSource source, {
        required bool isWeb,
        required TargetPlatform p,
      }) => uploadSourceNote(source, isWeb: isWeb, platform: p);

      const both =
          'Mac users: hold Command (⌘) and click photos to pick several.\n'
          'PC users: hold Ctrl and click photos to pick several.';
      for (final p in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        expect(note(UploadSource.cloud, isWeb: true, p: p), both);
        expect(note(UploadSource.device, isWeb: true, p: p), isNull);
      }
      // A phone's browser has no key to hold.
      expect(
        note(UploadSource.cloud, isWeb: true, p: TargetPlatform.iOS),
        isNull,
      );
      expect(
        note(UploadSource.cloud, isWeb: true, p: TargetPlatform.android),
        isNull,
      );
      // Android's picker starts ticking with a press and hold.
      expect(
        note(UploadSource.cloud, isWeb: false, p: TargetPlatform.android),
        'To pick several: press and hold the first photo until it is '
        'ticked, then tap the others, then tap Select.',
      );
      expect(
        note(UploadSource.device, isWeb: false, p: TargetPlatform.android),
        isNull,
      );
      // The iPhone's cloud is a folder, chosen from in the app.
      expect(
        note(UploadSource.cloud, isWeb: false, p: TargetPlatform.iOS),
        isNull,
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

    testWidgets('on Android, says under the cloud how to pick several, '
        'within a phone\'s width', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UploadSourceList(
              sources: const [UploadSource.device, UploadSource.cloud],
              onPick: (_) {},
            ),
          ),
        ),
      );

      final note = find.textContaining('press and hold the first photo');
      expect(note, findsOneWidget);
      expect(
        tester.getTopLeft(note).dy,
        greaterThan(tester.getBottomLeft(find.text('Google Drive')).dy),
      );
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('UploadSelectionGrid', () {
    final png = img.encodePng(img.Image(width: 4, height: 4));

    Future<List<PickedImage>> pumpGrid(
      WidgetTester tester, {
      int count = 0,
      bool selected = true,
      List<PickedImage>? given,
    }) async {
      final images =
          given ??
          [
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

    testWidgets('a preview that takes no taps, like a Drive photo\'s on the '
        'web, still ticks its photo when tapped', (tester) async {
      const previewKey = Key('drive preview');
      final images = await pumpGrid(
        tester,
        given: [
          PickedImage(
            name: 'drive.jpg',
            preview: null,
            previewBuilder: (_) =>
                const IgnorePointer(child: SizedBox.expand(key: previewKey)),
            read: () async => png,
          ),
        ],
      );
      expect(find.byKey(previewKey), findsOneWidget);

      await tester.tapAt(tester.getCenter(find.byKey(previewKey)));
      await tester.pump();

      expect(images.single.selected, isFalse);
      expect(find.text('0 of 1 selected'), findsOneWidget);
    });

    testWidgets('such a preview has the placeholder behind it, for while it '
        'loads or if it fails', (tester) async {
      await pumpGrid(
        tester,
        given: [
          PickedImage(
            name: 'drive.jpg',
            preview: null,
            previewBuilder: (_) => const SizedBox.expand(),
            read: () async => png,
          ),
        ],
      );

      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    });
  });
}
