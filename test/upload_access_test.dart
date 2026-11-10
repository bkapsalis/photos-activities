import 'dart:async';

import 'package:bills_bay_area/core/widgets/upload_access.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeUser implements User {
  _FakeUser(this.uid, {this.email, this.emailVerified = false});

  @override
  final String uid;
  @override
  final String? email;
  @override
  final bool emailVerified;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final visitor = _FakeUser('alice');
  final moderator = _FakeUser(
    'bill',
    email: 'bkapsalis@gmail.com',
    emailVerified: true,
  );

  Widget harness(Stream<bool> uploadsOpen, User user) => MaterialApp(
    home: Scaffold(
      body: UploadAccess(
        uploadsOpen: uploadsOpen,
        user: user,
        builder: (context, canUpload) =>
            canUpload ? const Text('Upload') : const SizedBox.shrink(),
      ),
    ),
  );

  testWidgets('hidden from a visitor while uploads are closed', (tester) async {
    await tester.pumpWidget(harness(Stream.value(false), visitor));
    await tester.pump();
    expect(find.text('Upload'), findsNothing);
  });

  testWidgets('shown to a moderator while uploads are closed', (tester) async {
    await tester.pumpWidget(harness(Stream.value(false), moderator));
    await tester.pump();
    expect(find.text('Upload'), findsOneWidget);
  });

  testWidgets('hidden until the switch has been read', (tester) async {
    final never = StreamController<bool>();
    addTearDown(never.close);
    await tester.pumpWidget(harness(never.stream, visitor));
    expect(find.text('Upload'), findsNothing);
  });

  testWidgets('hidden if the switch cannot be read', (tester) async {
    await tester.pumpWidget(
      harness(Stream.error(Exception('permission-denied')), visitor),
    );
    await tester.pump();
    expect(find.text('Upload'), findsNothing);
  });

  testWidgets('appears and disappears as the switch is flipped', (
    tester,
  ) async {
    final uploadsOpen = StreamController<bool>();
    addTearDown(uploadsOpen.close);
    await tester.pumpWidget(harness(uploadsOpen.stream, visitor));

    // A stream event reaches the widget a frame after it is added, so wait
    // for things to settle rather than for a single frame.
    uploadsOpen.add(true);
    await tester.pumpAndSettle();
    expect(find.text('Upload'), findsOneWidget);

    uploadsOpen.add(false);
    await tester.pumpAndSettle();
    expect(find.text('Upload'), findsNothing);
  });
}
