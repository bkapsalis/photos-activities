import 'package:bills_bay_area/core/data/mock_data.dart';
import 'package:bills_bay_area/core/models/models.dart';
import 'package:bills_bay_area/features/home/feed_navigator.dart';
import 'package:bills_bay_area/features/map/photo_location_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PhotoPost _photo({double? lat, double? lng}) => PhotoPost(
  id: 'p1',
  imageUrl: 'https://example.com/p1.jpg',
  location: Location(
    id: 'loc',
    name: 'Vasona Lake',
    region: 'Los Gatos, CA',
    postCount: 1,
    category: 'Hiking Areas',
    latitude: lat,
    longitude: lng,
  ),
  user: const UserProfile(
    id: 'u1',
    name: 'Bill',
    initials: 'BK',
    avatarColor: Color(0xFF4CAF50),
  ),
  heartCount: 0,
  category: 'Hiking Areas',
);

final _located = _photo(lat: 37.24, lng: -121.96);
final _unlocated = _photo();

/// Stands in for the photo page: just the map button, as both layouts use it.
Widget _photoPage(PhotoPost photo, {bool prominent = false}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: MapLocationButton(photo: photo, prominent: prominent),
    ),
  ),
);

Finder _buttonLabelled(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
);

VoidCallback? _onPressed(WidgetTester tester, String label) =>
    tester.widget<ButtonStyleButton>(_buttonLabelled(label)).onPressed;

void main() {
  setUp(() {
    // The real map is a native view a widget test cannot host.
    PhotoLocationScreen.debugMapBuilder = (_) =>
        const ColoredBox(key: Key('map'), color: Colors.green);
  });
  tearDown(() {
    PhotoLocationScreen.debugMapBuilder = null;
    FeedNavigator.requests.value = null;
  });

  group('the photo page button', () {
    for (final prominent in [false, true]) {
      final variant = prominent ? 'web' : 'mobile';

      testWidgets('$variant: "Map Where Image Was Taken" replaces directions', (
        tester,
      ) async {
        await tester.pumpWidget(_photoPage(_located, prominent: prominent));

        expect(find.text(MapLocationButton.label), findsOneWidget);
        expect(_onPressed(tester, MapLocationButton.label), isNotNull);
        expect(find.text(DirectionsButton.label), findsNothing);
        expect(find.text(MapLocationButton.unavailableNote), findsNothing);
      });

      testWidgets('$variant: no location means disabled, and says why', (
        tester,
      ) async {
        await tester.pumpWidget(_photoPage(_unlocated, prominent: prominent));

        expect(_onPressed(tester, MapLocationButton.label), isNull);
        expect(find.text(MapLocationButton.unavailableNote), findsOneWidget);
      });
    }
  });

  group('the map page', () {
    Future<void> openMap(WidgetTester tester) async {
      await tester.pumpWidget(_photoPage(_located));
      await tester.tap(find.text(MapLocationButton.label));
      await tester.pumpAndSettle();
    }

    testWidgets('opens in the app with the map, place and directions', (
      tester,
    ) async {
      await openMap(tester);

      expect(find.byType(PhotoLocationScreen), findsOneWidget);
      expect(find.byKey(const Key('map')), findsOneWidget);
      expect(find.text('Vasona Lake'), findsOneWidget);
      expect(find.text('Los Gatos, CA'), findsOneWidget);
      expect(find.text(DirectionsButton.label), findsOneWidget);
      expect(_onPressed(tester, DirectionsButton.label), isNotNull);
    });

    testWidgets('"Back" goes to the feed of the place the photo is from', (
      tester,
    ) async {
      // Feed at the bottom, the photo's page above it, then its map page.
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  const Text('the feed'),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            Scaffold(body: MapLocationButton(photo: _located)),
                      ),
                    ),
                    child: const Text('open photo'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(MapLocationButton.label));
      await tester.pumpAndSettle();

      expect(find.text('Back to Photo'), findsNothing);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();

      // Both pages above the feed are gone...
      expect(find.byType(PhotoLocationScreen), findsNothing);
      expect(find.byType(MapLocationButton), findsNothing);
      expect(find.text('the feed'), findsOneWidget);
      // ...and the feed has been asked for this photo's category and tab.
      final target = FeedNavigator.requests.value!;
      expect(categories[target.categoryIndex], 'Hiking Areas');
      expect(target.locationName, 'Vasona Lake');
      // ...with the photo itself, so the carousel can centre on it.
      expect(target.photoId, 'p1');
    });

    testWidgets('the back arrow returns to the photo page too', (tester) async {
      await openMap(tester);

      await tester.tap(find.byTooltip('Back to photo'));
      await tester.pumpAndSettle();

      expect(find.byType(PhotoLocationScreen), findsNothing);
    });
  });

  testWidgets('directions with no location: disabled, and says why', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DirectionsButton(photo: _unlocated)),
      ),
    );

    expect(_onPressed(tester, DirectionsButton.label), isNull);
    expect(find.text(DirectionsButton.unavailableNote), findsOneWidget);
  });

  group('FeedNavigator.categoryIndexFor', () {
    test('matches a category ignoring case and surrounding spaces', () {
      expect(FeedNavigator.categoryIndexFor('Hiking Areas', categories), 0);
      expect(
        FeedNavigator.categoryIndexFor(
          '  museums - historic sites ',
          categories,
        ),
        1,
      );
    });

    test('an unknown category matches nothing', () {
      expect(FeedNavigator.categoryIndexFor('Beaches', categories), isNull);
    });
  });
}
