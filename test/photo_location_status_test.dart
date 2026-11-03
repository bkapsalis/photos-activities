import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bills_bay_area/core/models/photo_metadata.dart';
import 'package:bills_bay_area/core/widgets/shared_widgets.dart';
import 'package:bills_bay_area/features/home/widgets/upload_photo_dialog.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    PhotoMetadata metadata, {
    bool finding = false,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PhotoLocationStatus(metadata: metadata, finding: finding),
      ),
    ),
  );

  testWidgets('says when the location came from the photo', (tester) async {
    await pump(
      tester,
      const PhotoMetadata(
        latitude: 37.47,
        longitude: -122.31,
        locationSource: LocationSource.exif,
      ),
    );
    expect(find.text('Location from the photo'), findsOneWidget);
  });

  testWidgets('says when the location is where the phone is', (tester) async {
    await pump(tester, PhotoMetadata.empty.withDeviceLocation(37.79, -122.4));
    expect(find.text('Location: where you are now'), findsOneWidget);
  });

  testWidgets('says it is still looking', (tester) async {
    await pump(tester, PhotoMetadata.empty, finding: true);
    expect(find.text('Finding your location…'), findsOneWidget);
  });

  testWidgets('warns when the photo will not map', (tester) async {
    await pump(tester, PhotoMetadata.empty);
    expect(
      find.text('No location — this photo won\'t appear on the map'),
      findsOneWidget,
    );
  });

  group('IncludeLocationSwitch', () {
    Future<List<bool>> pumpSwitch(
      WidgetTester tester, {
      required bool value,
      bool plural = false,
    }) async {
      final changes = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IncludeLocationSwitch(
              value: value,
              plural: plural,
              onChanged: changes.add,
            ),
          ),
        ),
      );
      return changes;
    }

    testWidgets('is on to begin with, and a tap turns it off', (tester) async {
      final changes = await pumpSwitch(tester, value: true);

      expect(find.text('Include where this photo was taken'), findsOneWidget);
      expect(find.text('Shown on the map'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      expect(changes, [false]);
    });

    testWidgets('off, says the photo will not map', (tester) async {
      await pumpSwitch(tester, value: false);
      expect(
        find.text('Left out: it won\'t appear on the map'),
        findsOneWidget,
      );
    });

    testWidgets('speaks of several photos when there are', (tester) async {
      await pumpSwitch(tester, value: false, plural: true);
      expect(
        find.text('Include where these photos were taken'),
        findsOneWidget,
      );
      expect(
        find.text('Left out: they won\'t appear on the map'),
        findsOneWidget,
      );
    });
  });
}
