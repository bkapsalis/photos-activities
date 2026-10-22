import 'package:bills_bay_area/core/widgets/like_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget harness({required bool liked, VoidCallback? onTap}) => MaterialApp(
    home: Scaffold(
      body: LikeView(liked: liked, count: 7, onTap: onTap),
    ),
  );

  testWidgets('an unliked photo shows an outline heart', (tester) async {
    await tester.pumpWidget(harness(liked: false));
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsNothing);
    expect(find.text('7'), findsOneWidget);
  });

  testWidgets('a liked photo shows a filled heart', (tester) async {
    await tester.pumpWidget(harness(liked: true));
    expect(find.byIcon(Icons.favorite), findsOneWidget);
  });

  testWidgets('tapping asks to toggle the like', (tester) async {
    var taps = 0;
    await tester.pumpWidget(harness(liked: false, onTap: () => taps++));
    await tester.tap(find.byType(LikeView));
    expect(taps, 1);
  });
}
