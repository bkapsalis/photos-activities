import 'package:bills_bay_area/core/utils/user_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<bool?> run(WidgetTester tester, Future<void> Function() action) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await runUserAction(
                context,
                action,
                failureMessage: 'Your comment was not posted.',
              ),
              child: const Text('Go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('a successful action reports success quietly', (tester) async {
    final result = await run(tester, () async {});
    expect(result, isTrue);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a failed action is explained instead of thrown', (tester) async {
    final result = await run(
      tester,
      () async => throw Exception('permission-denied'),
    );
    expect(result, isFalse);
    expect(find.text('Your comment was not posted.'), findsOneWidget);
  });
}
