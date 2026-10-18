import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bills_bay_area/features/home/widgets/map_toggle.dart';

void main() {
  final scroll = ScrollController();
  tearDownAll(scroll.dispose);

  Widget host({required bool showMap, bool keepFeed = true}) => MaterialApp(
    home: Scaffold(
      body: FeedUnderMap(
        showMap: showMap,
        keepFeed: keepFeed,
        map: const Center(child: Text('the map')),
        feed: ListView.builder(
          controller: scroll,
          itemCount: 200,
          itemBuilder: (_, i) => SizedBox(height: 80, child: Text('photo $i')),
        ),
      ),
    ),
  );

  testWidgets('the feed keeps its scroll position through the map', (
    tester,
  ) async {
    await tester.pumpWidget(host(showMap: false));
    scroll.jumpTo(4000);
    await tester.pump();
    expect(find.text('photo 50'), findsOneWidget);

    await tester.pumpWidget(host(showMap: true));
    expect(find.text('the map'), findsOneWidget);
    // Hidden, not gone: nothing of the feed shows or takes taps.
    expect(find.text('photo 50'), findsNothing);
    expect(scroll.offset, 4000);

    await tester.pumpWidget(host(showMap: false));
    expect(find.text('the map'), findsNothing);
    expect(find.text('photo 50'), findsOneWidget);
    expect(scroll.offset, 4000);
  });

  testWidgets('a feed nobody returns to is not built under the map', (
    tester,
  ) async {
    await tester.pumpWidget(host(showMap: true, keepFeed: false));
    expect(find.text('the map'), findsOneWidget);
    expect(find.text('photo 0', skipOffstage: false), findsNothing);
  });
}
