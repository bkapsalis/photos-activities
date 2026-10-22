import 'dart:async';

import 'package:bills_bay_area/core/widgets/live_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late int subscriptions;
  late List<StreamController<String>> controllers;

  Stream<String> source() {
    subscriptions++;
    final controller = StreamController<String>();
    controllers.add(controller);
    return controller.stream;
  }

  setUp(() {
    subscriptions = 0;
    controllers = [];
  });

  tearDown(() async {
    for (final c in controllers) {
      await c.close();
    }
  });

  Widget harness({Object? identity, String label = ''}) => MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          Text('label $label'),
          Expanded(
            child: LiveData<String>(
              identity: identity,
              stream: source,
              errorMessage: 'Comments could not be loaded.',
              builder: (context, value) => Text('value $value'),
            ),
          ),
        ],
      ),
    ),
  );

  testWidgets('shows a spinner, then the data', (tester) async {
    await tester.pumpWidget(harness());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    controllers.last.add('hello');
    await tester.pumpAndSettle();
    expect(find.text('value hello'), findsOneWidget);
  });

  testWidgets('a rebuild keeps the same subscription', (tester) async {
    await tester.pumpWidget(harness(label: 'a'));
    await tester.pumpWidget(harness(label: 'b'));
    await tester.pumpWidget(harness(label: 'c'));
    expect(subscriptions, 1);
  });

  testWidgets('a new identity subscribes again', (tester) async {
    await tester.pumpWidget(harness(identity: 'photo1'));
    await tester.pumpWidget(harness(identity: 'photo2'));
    expect(subscriptions, 2);
  });

  testWidgets('a failure is shown as a failure, with a retry', (tester) async {
    await tester.pumpWidget(harness());
    controllers.last.addError(Exception('permission-denied'));
    await tester.pumpAndSettle();
    expect(find.text('Comments could not be loaded.'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(subscriptions, 2);
    controllers.last.add('back');
    await tester.pumpAndSettle();
    expect(find.text('value back'), findsOneWidget);
  });

  testWidgets('null is an answer for a nullable stream, not "loading"', (
    tester,
  ) async {
    final photo = StreamController<String?>();
    addTearDown(photo.close);
    await tester.pumpWidget(
      MaterialApp(
        home: LiveData<String?>(
          stream: () => photo.stream,
          errorMessage: 'This photo could not be loaded.',
          builder: (context, value) => Text(value ?? 'not found'),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    photo.add(null);
    await tester.pumpAndSettle();
    expect(find.text('not found'), findsOneWidget);
  });
}
