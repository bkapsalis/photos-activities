import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bills_bay_area/core/models/models.dart';
import 'package:bills_bay_area/features/home/widgets/location_tab_bar.dart';

PhotoPost _photo(String id, String locationName) => PhotoPost(
      id: id,
      imageUrl: 'https://example.com/$id.jpg',
      location: Location(
        id: locationName.toLowerCase(),
        name: locationName,
        postCount: 0,
        category: 'Hiking Areas',
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

void main() {
  group('LocationTabs.fromPhotos', () {
    test('collects distinct names with per-location counts', () {
      final tabs = LocationTabs.fromPhotos([
        _photo('1', 'Vasona Lake'),
        _photo('2', 'Vasona Lake'),
        _photo('3', 'Bay Area Hiking'),
      ]);

      expect(tabs.names, ['Bay Area Hiking', 'Vasona Lake']);
      expect(tabs.counts['Vasona Lake'], 2);
      expect(tabs.counts['Bay Area Hiking'], 1);
      expect(tabs.totalCount, 3);
    });

    test('sorts case-insensitively and skips blank location names', () {
      final tabs = LocationTabs.fromPhotos([
        _photo('1', 'zebra ridge'),
        _photo('2', 'Alum Rock'),
        _photo('3', '   '),
      ]);

      expect(tabs.names, ['Alum Rock', 'zebra ridge']);
      expect(tabs.totalCount, 3);
    });

    test('resolve falls back to All when the location is gone', () {
      final tabs = LocationTabs.fromPhotos([_photo('1', 'Vasona Lake')]);

      expect(tabs.resolve('Vasona Lake'), 'Vasona Lake');
      expect(tabs.resolve('Deleted Park'), isNull);
      expect(tabs.resolve(null), isNull);
    });
  });

  group('LocationTabBar', () {
    Widget harness({
      required LocationTabs tabs,
      String? selected,
      required ValueChanged<String?> onChanged,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: LocationTabBar(
            tabs: tabs,
            selectedLocation: selected,
            onLocationChanged: onChanged,
          ),
        ),
      );
    }

    testWidgets('renders an All tab plus one tab per location', (tester) async {
      final tabs = LocationTabs.fromPhotos([
        _photo('1', 'Vasona Lake'),
        _photo('2', 'Vasona Lake'),
        _photo('3', 'Bay Area Hiking'),
      ]);

      await tester.pumpWidget(harness(tabs: tabs, onChanged: (_) {}));

      expect(find.text('All (3)'), findsOneWidget);
      expect(find.text('Vasona Lake (2)'), findsOneWidget);
      expect(find.text('Bay Area Hiking (1)'), findsOneWidget);
    });

    testWidgets('reports the tapped location', (tester) async {
      String? picked = 'unset';
      final tabs = LocationTabs.fromPhotos([
        _photo('1', 'Vasona Lake'),
        _photo('2', 'Bay Area Hiking'),
      ]);

      await tester.pumpWidget(
        harness(tabs: tabs, onChanged: (loc) => picked = loc),
      );

      await tester.tap(find.text('Vasona Lake (1)'));
      await tester.pumpAndSettle();
      expect(picked, 'Vasona Lake');
    });

    testWidgets('tapping All reports null', (tester) async {
      String? picked = 'unset';
      final tabs = LocationTabs.fromPhotos([
        _photo('1', 'Vasona Lake'),
        _photo('2', 'Bay Area Hiking'),
      ]);

      await tester.pumpWidget(
        harness(
          tabs: tabs,
          selected: 'Vasona Lake',
          onChanged: (loc) => picked = loc,
        ),
      );

      await tester.tap(find.text('All (2)'));
      await tester.pumpAndSettle();
      expect(picked, isNull);
    });

    testWidgets('survives the location list growing and shrinking',
        (tester) async {
      final two = LocationTabs.fromPhotos([
        _photo('1', 'Vasona Lake'),
        _photo('2', 'Bay Area Hiking'),
      ]);
      final three = LocationTabs.fromPhotos([
        _photo('1', 'Vasona Lake'),
        _photo('2', 'Bay Area Hiking'),
        _photo('3', 'Alum Rock'),
      ]);

      await tester.pumpWidget(harness(tabs: two, onChanged: (_) {}));
      expect(find.text('Alum Rock (1)'), findsNothing);

      // A new photo introduces a location: the controller must be rebuilt.
      await tester.pumpWidget(harness(tabs: three, onChanged: (_) {}));
      await tester.pumpAndSettle();
      expect(find.text('Alum Rock (1)'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // ...and back down again.
      await tester.pumpWidget(harness(tabs: two, onChanged: (_) {}));
      await tester.pumpAndSettle();
      expect(find.text('Alum Rock (1)'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders nothing when the category has no locations',
        (tester) async {
      await tester.pumpWidget(
        harness(tabs: LocationTabs.fromPhotos([]), onChanged: (_) {}),
      );

      expect(find.byType(TabBar), findsNothing);
    });
  });
}
