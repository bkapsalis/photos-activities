import 'package:bills_bay_area/core/models/models.dart';
import 'package:bills_bay_area/core/services/view_mode_service.dart';
import 'package:bills_bay_area/features/home/widgets/photo_carousel_view.dart';
import 'package:bills_bay_area/features/home/widgets/photo_feed_view.dart';
import 'package:bills_bay_area/features/home/widgets/view_mode_toggle_button.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_cache_manager.dart';
import 'helpers/test_photos.dart';

/// Wires the toggle to the feed the way HomeScreen does: the mode is held
/// above both, flipped by the button and saved through [ViewModeService].
/// The real grid needs Firebase (PhotoCard checks who may edit), so a
/// stand-in takes its place; the carousel is the real one.
class _FeedWithToggle extends StatefulWidget {
  final List<PhotoPost> photos;
  final PhotoViewMode initialMode;

  const _FeedWithToggle({required this.photos, required this.initialMode});

  @override
  State<_FeedWithToggle> createState() => _FeedWithToggleState();
}

class _FeedWithToggleState extends State<_FeedWithToggle> {
  final _service = ViewModeService();
  late var _mode = widget.initialMode;

  void _toggle() {
    final next = _mode.toggled;
    setState(() => _mode = next);
    _service.save(next);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          actions: [ViewModeToggleButton(mode: _mode, onPressed: _toggle)],
        ),
        body: PhotoFeedView(
          mode: _mode,
          photos: widget.photos,
          masonry: const Center(key: Key('masonry'), child: Text('grid')),
        ),
      ),
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CachedNetworkImageProvider.defaultCacheManager = FakeCacheManager();
    imageCache.clear();
  });

  group('PhotoViewMode', () {
    test('toggled flips between the two layouts', () {
      expect(PhotoViewMode.masonry.toggled, PhotoViewMode.carousel);
      expect(PhotoViewMode.carousel.toggled, PhotoViewMode.masonry);
    });
  });

  group('ViewModeService', () {
    test('defaults to the grid when nothing has been saved', () async {
      expect(await ViewModeService().load(), PhotoViewMode.masonry);
    });

    test('a saved choice is what a fresh start loads', () async {
      await ViewModeService().save(PhotoViewMode.carousel);
      // A new instance stands in for the app restarting.
      expect(await ViewModeService().load(), PhotoViewMode.carousel);
    });

    test('an unrecognised stored value falls back to the grid', () async {
      SharedPreferences.setMockInitialValues({
        ViewModeService.prefsKey: 'filmstrip',
      });
      expect(await ViewModeService().load(), PhotoViewMode.masonry);
    });
  });

  group('toggling between modes', () {
    testWidgets('the label says what a tap will do, shows for a moment '
        'after one, and is what screen readers hear', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _FeedWithToggle(
          photos: testPhotos(3),
          initialMode: PhotoViewMode.masonry,
        ),
      );

      expect(find.byTooltip('Change to Carousel View'), findsOneWidget);
      expect(find.text('Change to Carousel View'), findsNothing);
      expect(find.bySemanticsLabel('Change to Carousel View'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.view_carousel_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      // Now in the carousel, so the label offers the way back.
      expect(find.text('Change to Masonry View'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Change to Masonry View'), findsNothing);
      expect(find.bySemanticsLabel('Change to Masonry View'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('a press and hold shows the label too', (tester) async {
      await tester.pumpWidget(
        _FeedWithToggle(
          photos: testPhotos(3),
          initialMode: PhotoViewMode.masonry,
        ),
      );

      await tester.longPress(find.byIcon(Icons.view_carousel_outlined));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Change to Carousel View'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    });

    testWidgets('switches grid -> carousel -> grid and saves each choice', (
      tester,
    ) async {
      await tester.pumpWidget(
        _FeedWithToggle(
          photos: testPhotos(3),
          initialMode: PhotoViewMode.masonry,
        ),
      );

      expect(find.byKey(const Key('masonry')), findsOneWidget);
      expect(find.byType(PhotoCarouselView), findsNothing);
      expect(find.byIcon(Icons.view_carousel_outlined), findsOneWidget);

      await tester.tap(find.byIcon(Icons.view_carousel_outlined));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('masonry')), findsNothing);
      expect(find.byType(PhotoCarouselView), findsOneWidget);
      expect(find.byKey(const ValueKey('carousel-thumb-p0')), findsOneWidget);
      expect(find.byIcon(Icons.grid_view), findsOneWidget);
      expect(await ViewModeService().load(), PhotoViewMode.carousel);

      await tester.tap(find.byIcon(Icons.grid_view));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('masonry')), findsOneWidget);
      expect(find.byType(PhotoCarouselView), findsNothing);
      expect(await ViewModeService().load(), PhotoViewMode.masonry);
    });

    testWidgets('both layouts show the very same list of photos', (
      tester,
    ) async {
      final photos = testPhotos(4);
      await tester.pumpWidget(
        _FeedWithToggle(photos: photos, initialMode: PhotoViewMode.carousel),
      );
      await tester.pumpAndSettle();

      final carousel = tester.widget<PhotoCarouselView>(
        find.byType(PhotoCarouselView),
      );
      expect(identical(carousel.photos, photos), isTrue);
    });
  });
}
