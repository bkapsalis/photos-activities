import 'package:bills_bay_area/core/models/models.dart';
import 'package:bills_bay_area/core/utils/carousel_selection.dart';
import 'package:bills_bay_area/features/home/widgets/full_screen_photo_view.dart';
import 'package:bills_bay_area/features/home/widgets/photo_carousel_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:carousel_slider/carousel_slider.dart' show CarouselSlider;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_cache_manager.dart';
import 'helpers/test_photos.dart';

Widget _app(
  List<PhotoPost> photos, {
  Function(String)? onPhotoTap,
  String? focusPhotoId,
  int focusRequest = 0,
}) {
  return MaterialApp(
    home: Scaffold(
      body: PhotoCarouselView(
        photos: photos,
        onPhotoTap: onPhotoTap,
        focusPhotoId: focusPhotoId,
        focusRequest: focusRequest,
      ),
    ),
  );
}

Finder _thumb(String id) => find.byKey(ValueKey('carousel-thumb-$id'));

/// The large photo, when it is showing [id]. Only the large photo carries a
/// Hero, so its tag identifies both the widget and which photo it shows.
Finder _large(String id) => find.byWidgetPredicate(
  (w) => w is Hero && w.tag == FullScreenPhotoView.heroTag(id),
);

/// The strip's scroll position, in thumbnails from the first.
double _stripPage(WidgetTester tester) =>
    tester.widget<PageView>(find.byType(PageView)).controller!.page!;

bool _thumbIsSelected(WidgetTester tester, String id) {
  final semantics = tester.widget<Semantics>(
    find.ancestor(of: _thumb(id), matching: find.byType(Semantics)).first,
  );
  return semantics.properties.selected ?? false;
}

void main() {
  late FakeCacheManager cache;

  setUp(() {
    cache = FakeCacheManager();
    CachedNetworkImageProvider.defaultCacheManager = cache;
    imageCache.clear();
  });

  group('resolveCarouselSelection', () {
    final photos = testPhotos(4);

    test('follows the selected photo when the list is re-sorted', () {
      final resorted = [photos[2], photos[0], photos[1], photos[3]];
      expect(resolveCarouselSelection(resorted, 'p2'), 0);
      expect(resolveCarouselSelection(resorted, 'p3'), 3);
    });

    test('starts over from the first photo when the selection is gone', () {
      expect(resolveCarouselSelection(photos, 'deleted'), 0);
      expect(resolveCarouselSelection(photos, null), 0);
      expect(resolveCarouselSelection(const [], 'p1'), 0);
    });
  });

  group('PhotoCarouselView', () {
    testWidgets('opens on the first photo, shown large and highlighted', (
      tester,
    ) async {
      await tester.pumpWidget(_app(testPhotos(4)));
      await tester.pumpAndSettle();

      expect(_large('p0'), findsOneWidget);
      expect(find.text('Spot 0'), findsOneWidget);
      expect(find.text('Bill · 1 of 4'), findsOneWidget);
      expect(_thumbIsSelected(tester, 'p0'), isTrue);
      expect(_thumbIsSelected(tester, 'p1'), isFalse);
      // Every thumbnail and the large photo go through the image cache.
      expect(cache.requested, contains('https://example.com/p0.jpg'));
    });

    testWidgets('tapping a thumbnail selects it and shows it large', (
      tester,
    ) async {
      await tester.pumpWidget(_app(testPhotos(4)));
      await tester.pumpAndSettle();

      await tester.tap(_thumb('p2'));
      await tester.pumpAndSettle();

      expect(_large('p2'), findsOneWidget);
      expect(_large('p0'), findsNothing);
      expect(find.text('Spot 2'), findsOneWidget);
      expect(find.text('Bill · 3 of 4'), findsOneWidget);
      expect(_thumbIsSelected(tester, 'p2'), isTrue);
      expect(_thumbIsSelected(tester, 'p0'), isFalse);
    });

    testWidgets('swiping the strip changes the large photo', (tester) async {
      await tester.pumpWidget(_app(testPhotos(4)));
      await tester.pumpAndSettle();

      // A slow drag of a little over one thumbnail settles on the next one.
      await tester.timedDrag(
        find.byType(CarouselSlider),
        const Offset(-110, 0),
        const Duration(milliseconds: 800),
      );
      await tester.pumpAndSettle();

      expect(_large('p1'), findsOneWidget);
      expect(_large('p0'), findsNothing);
      expect(_thumbIsSelected(tester, 'p1'), isTrue);
    });

    testWidgets('trackpad or mouse-wheel scrolling changes the large photo', (
      tester,
    ) async {
      // Web scrolling with no press on the strip — the case carousel_slider
      // labels as a controller move rather than a manual one.
      await tester.pumpWidget(_app(testPhotos(4)));
      await tester.pumpAndSettle();

      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      final strip = tester.getCenter(find.byType(CarouselSlider));
      await tester.sendEventToBinding(mouse.hover(strip));
      await tester.sendEventToBinding(mouse.scroll(const Offset(110, 0)));
      await tester.pumpAndSettle();

      expect(_large('p0'), findsNothing);
      final shown = [
        for (final id in ['p1', 'p2', 'p3'])
          if (_large(id).evaluate().isNotEmpty) id,
      ];
      expect(shown, hasLength(1));
      // The large photo is whichever thumbnail the scroll centred.
      expect(_thumbIsSelected(tester, shown.single), isTrue);
    });

    testWidgets('a flick coasts past several thumbnails, slowing to a stop', (
      tester,
    ) async {
      await tester.pumpWidget(_app(testPhotos(20)));
      await tester.pumpAndSettle();

      // A quick flick: the finger lifts while the strip is still moving fast.
      await tester.fling(
        find.byType(CarouselSlider),
        const Offset(-200, 0),
        2500,
      );

      // Sample the glide frame by frame after the finger has lifted.
      final positions = <double>[];
      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        positions.add(_stripPage(tester));
      }
      await tester.pumpAndSettle();

      final steps = [
        for (var i = 1; i < positions.length; i++)
          positions[i] - positions[i - 1],
      ].where((s) => s.abs() > 1e-6).toList();

      // It kept moving for a good while after the release...
      expect(steps.length, greaterThan(15));
      // ...always forward, and each stretch slower than the last.
      expect(steps.every((s) => s > 0), isTrue);
      for (var i = 1; i < steps.length; i++) {
        expect(steps[i], lessThanOrEqualTo(steps[i - 1] + 1e-6));
      }

      // It travelled further than PageView's one-page-per-fling...
      final page = _stripPage(tester);
      expect(page, greaterThan(2));
      // ...and came to rest with a thumbnail centred — to within a pixel, the
      // rest tolerance every Flutter scroll simulation stops inside — and that
      // thumbnail is the one shown large.
      expect(page, closeTo(page.roundToDouble(), 0.01));
      final id = 'p${page.round()}';
      expect(_large(id), findsOneWidget);
      expect(_thumbIsSelected(tester, id), isTrue);
    });

    testWidgets('a short, slow drag still settles on the nearest thumbnail', (
      tester,
    ) async {
      await tester.pumpWidget(_app(testPhotos(6)));
      await tester.pumpAndSettle();

      // Less than half a thumbnail, released with almost no speed.
      await tester.timedDrag(
        find.byType(CarouselSlider),
        const Offset(-40, 0),
        const Duration(milliseconds: 800),
      );
      await tester.pumpAndSettle();

      expect(_stripPage(tester), closeTo(0, 0.01));
      expect(_large('p0'), findsOneWidget);
    });

    testWidgets('opens centred on the photo the reader came back from', (
      tester,
    ) async {
      // Coming back from a photo's map page: that photo, not the first.
      await tester.pumpWidget(_app(testPhotos(6), focusPhotoId: 'p4'));
      await tester.pumpAndSettle();

      expect(_large('p4'), findsOneWidget);
      expect(_thumbIsSelected(tester, 'p4'), isTrue);
      expect(_thumbIsSelected(tester, 'p0'), isFalse);
      expect(_stripPage(tester), closeTo(4, 0.01));
      expect(find.text('Bill · 5 of 6'), findsOneWidget);
    });

    testWidgets('an already-open carousel moves to a newly requested photo', (
      tester,
    ) async {
      final photos = testPhotos(6);
      await tester.pumpWidget(_app(photos));
      await tester.pumpAndSettle();
      await tester.tap(_thumb('p1'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        _app(photos, focusPhotoId: 'p3', focusRequest: 1),
      );
      await tester.pumpAndSettle();
      expect(_large('p3'), findsOneWidget);
      expect(_stripPage(tester), closeTo(3, 0.01));

      // The same photo asked for again, after the reader has moved off it.
      await tester.tap(_thumb('p0'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        _app(photos, focusPhotoId: 'p3', focusRequest: 2),
      );
      await tester.pumpAndSettle();
      expect(_large('p3'), findsOneWidget);
      expect(_thumbIsSelected(tester, 'p3'), isTrue);
    });

    testWidgets('a requested photo not in this tab falls back to the first', (
      tester,
    ) async {
      await tester.pumpWidget(_app(testPhotos(3), focusPhotoId: 'gone'));
      await tester.pumpAndSettle();

      expect(_large('p0'), findsOneWidget);
    });

    testWidgets('a tap still skips the photos it slides past', (tester) async {
      final seen = <String>{};
      await tester.pumpWidget(_app(testPhotos(5)));
      await tester.pumpAndSettle();

      await tester.tap(_thumb('p3'));
      // Sample every frame of the slide: only the target may appear large.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        for (final id in ['p0', 'p1', 'p2', 'p3', 'p4']) {
          if (_large(id).evaluate().isNotEmpty) seen.add(id);
        }
      }
      await tester.pumpAndSettle();

      expect(seen, {'p3'});
      expect(_large('p3'), findsOneWidget);
    });

    testWidgets('keeps the same photo when the live list is re-sorted', (
      tester,
    ) async {
      final photos = testPhotos(4);
      await tester.pumpWidget(_app(photos));
      await tester.pumpAndSettle();
      await tester.tap(_thumb('p2'));
      await tester.pumpAndSettle();

      // Firestore re-emits with p2 now most-liked, so it sorts first.
      await tester.pumpWidget(
        _app([photos[2], photos[0], photos[1], photos[3]]),
      );
      await tester.pumpAndSettle();

      expect(_large('p2'), findsOneWidget);
      expect(find.text('Bill · 1 of 4'), findsOneWidget);
      expect(_thumbIsSelected(tester, 'p2'), isTrue);
    });

    testWidgets('"Image Details and Directions" opens the selected '
        "photo's own page", (tester) async {
      String? opened;
      await tester.pumpWidget(
        _app(testPhotos(3), onPhotoTap: (id) => opened = id),
      );
      await tester.pumpAndSettle();
      await tester.tap(_thumb('p1'));
      await tester.pumpAndSettle();

      expect(find.text('Details'), findsNothing);
      await tester.tap(find.text('Image Details and Directions'));
      expect(opened, 'p1');
    });

    testWidgets('on a phone-width screen the long link gets its own line '
        'and the place name still shows', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(testPhotos(3), onPhotoTap: (_) {}));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull); // no overflow
      final link = find.text('Image Details and Directions');
      final place = find.text('Spot 0');
      expect(link, findsOneWidget);
      expect(place, findsOneWidget);
      // Below the place name, not squeezed beside it.
      expect(
        tester.getTopLeft(link).dy,
        greaterThan(tester.getBottomLeft(place).dy),
      );
      expect(tester.getSize(place).width, greaterThan(30));
    });

    testWidgets('a photo that fails to load shows the error state', (
      tester,
    ) async {
      CachedNetworkImageProvider.defaultCacheManager = FakeCacheManager(
        failingUrls: {'https://example.com/p0.jpg'},
      );
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_app(testPhotos(2)));
      await tester.pumpAndSettle();

      // The failing photo is both the first thumbnail and the large view. Its
      // label merges into the enclosing button's, so match it as a part.
      expect(
        find.bySemanticsLabel(RegExp('Photo could not be loaded')),
        findsWidgets,
      );
      expect(find.byIcon(Icons.broken_image_outlined), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  });

  group('full-screen view', () {
    testWidgets('opens from the large photo with zoom, and Back returns to '
        'the same photo', (tester) async {
      await tester.pumpWidget(_app(testPhotos(4)));
      await tester.pumpAndSettle();
      await tester.tap(_thumb('p2'));
      await tester.pumpAndSettle();

      await tester.tap(_large('p2'));
      await tester.pumpAndSettle();

      expect(find.byType(FullScreenPhotoView), findsOneWidget);
      final viewer = find.descendant(
        of: find.byType(FullScreenPhotoView),
        matching: find.byType(InteractiveViewer),
      );
      expect(viewer, findsOneWidget);
      expect(tester.widget<InteractiveViewer>(viewer).maxScale, greaterThan(1));
      // Same Hero tag on both ends is what animates the photo between them.
      final heroFinder = find.descendant(
        of: find.byType(FullScreenPhotoView),
        matching: find.byType(Hero),
      );
      expect(
        tester.widget<Hero>(heroFinder).tag,
        FullScreenPhotoView.heroTag('p2'),
      );
      // The photo gets the whole screen, not just the back button's corner.
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(tester.getSize(heroFinder), screen);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.byType(FullScreenPhotoView), findsNothing);
      expect(_large('p2'), findsOneWidget);
      expect(_thumbIsSelected(tester, 'p2'), isTrue);
    });

    testWidgets('tapping the photo closes it', (tester) async {
      await tester.pumpWidget(_app(testPhotos(3)));
      await tester.pumpAndSettle();
      await tester.tap(_thumb('p1'));
      await tester.pumpAndSettle();
      await tester.tap(_large('p1'));
      await tester.pumpAndSettle();
      expect(find.byType(FullScreenPhotoView), findsOneWidget);

      await tester.tap(find.byType(InteractiveViewer));
      await tester.pumpAndSettle();

      expect(find.byType(FullScreenPhotoView), findsNothing);
      expect(_large('p1'), findsOneWidget);
      expect(_thumbIsSelected(tester, 'p1'), isTrue);
    });

    testWidgets('dragging the photo does not close it', (tester) async {
      await tester.pumpWidget(_app(testPhotos(2)));
      await tester.pumpAndSettle();
      await tester.tap(_large('p0'));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(InteractiveViewer), const Offset(80, 40));
      await tester.pumpAndSettle();

      expect(find.byType(FullScreenPhotoView), findsOneWidget);
    });

    testWidgets('Escape closes it too', (tester) async {
      await tester.pumpWidget(_app(testPhotos(2)));
      await tester.pumpAndSettle();
      await tester.tap(_large('p0'));
      await tester.pumpAndSettle();
      expect(find.byType(FullScreenPhotoView), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(FullScreenPhotoView), findsNothing);
      expect(_large('p0'), findsOneWidget);
    });
  });
}
