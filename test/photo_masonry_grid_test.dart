import 'package:bills_bay_area/core/models/models.dart';
import 'package:bills_bay_area/features/home/widgets/photo_masonry_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_photos.dart';

/// A plain tile of varying height, standing in for PhotoCard.
Widget _tile(PhotoPost photo, VoidCallback onTap) => GestureDetector(
  key: ValueKey('tile-${photo.id}'),
  onTap: onTap,
  child: SizedBox(
    height: 150.0 + (photo.id.hashCode % 5) * 30,
    child: ColoredBox(color: Colors.grey, child: Text(photo.id)),
  ),
);

Finder _tileOf(String id) => find.byKey(ValueKey('tile-$id'));

void main() {
  late ScrollController controller;
  late int doneCalls;

  setUp(() {
    controller = ScrollController();
    doneCalls = 0;
  });
  tearDown(() => controller.dispose());

  Widget grid(List<PhotoPost> photos, {String? focus}) => MaterialApp(
    home: Scaffold(
      body: PhotoMasonryGrid(
        photos: photos,
        controller: controller,
        physics: const AlwaysScrollableScrollPhysics(),
        crossAxisCount: 2,
        spacing: 12,
        padding: const EdgeInsets.all(16),
        focusPhotoId: focus,
        onFocusDone: () => doneCalls++,
        tileBuilder: _tile,
      ),
    ),
  );

  /// Lets the step-by-step scroll, the settle and the outline's fade run.
  Future<void> runFocus(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('scrolls a photo far down the grid into view', (tester) async {
    await tester.pumpWidget(grid(testPhotos(60), focus: 'p52'));
    await runFocus(tester);

    // Far enough down that it started off screen, not built at all.
    expect(controller.offset, greaterThan(1500));
    final tile = tester.getRect(_tileOf('p52'));
    final screen =
        Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);
    expect(screen.contains(tile.topCenter), isTrue);
    expect(screen.contains(tile.bottomCenter), isTrue);
    expect(doneCalls, 1);
  });

  testWidgets('outlines the photo thickly for about 5 seconds', (tester) async {
    bool outlined() => tester
        .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
        .any((o) => o.opacity == 1);

    await tester.pumpWidget(grid(testPhotos(30), focus: 'p20'));
    for (var i = 0; i < 20 && !outlined(); i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(outlined(), isTrue);

    final border =
        (tester
                    .widget<DecoratedBox>(
                      find.descendant(
                        of: find.byType(AnimatedOpacity),
                        matching: find.byType(DecoratedBox),
                      ),
                    )
                    .decoration
                as BoxDecoration)
            .border!
            .top;
    expect(border.width, 8);

    // Still there four and a half seconds in...
    await tester.pump(const Duration(milliseconds: 4500));
    expect(outlined(), isTrue);

    // ...and gone a second later, once five seconds have passed.
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();
    expect(outlined(), isFalse);
  });

  testWidgets('a photo that is not in this tab leaves the grid at the top', (
    tester,
  ) async {
    await tester.pumpWidget(grid(testPhotos(30), focus: 'deleted'));
    await runFocus(tester);

    expect(controller.offset, 0);
    expect(doneCalls, 1);
  });

  testWidgets('with no photo to return to, the grid stays at the top', (
    tester,
  ) async {
    await tester.pumpWidget(grid(testPhotos(30)));
    await runFocus(tester);

    expect(controller.offset, 0);
    expect(doneCalls, 0);
  });

  testWidgets('tapping a tile still opens that photo', (tester) async {
    String? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhotoMasonryGrid(
            photos: testPhotos(4),
            controller: controller,
            physics: const AlwaysScrollableScrollPhysics(),
            crossAxisCount: 2,
            spacing: 12,
            padding: const EdgeInsets.all(16),
            onPhotoTap: (id) => opened = id,
            tileBuilder: _tile,
          ),
        ),
      ),
    );

    await tester.tap(_tileOf('p3'));
    expect(opened, 'p3');
  });
}
