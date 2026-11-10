import 'package:bills_bay_area/core/services/moderation_service.dart';
import 'package:bills_bay_area/features/moderation/delete_account_of_dialog.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _pat = AccountToDelete(
  uid: 'u1',
  name: 'Pat',
  email: 'pat@example.com',
  signInWith: const ['google.com'],
  createdAt: DateTime(2026, 11, 2),
  lastSignInAt: DateTime(2026, 11, 5),
  photos: 1,
  messages: 2,
  likes: 3,
);

void main() {
  group('AccountToDelete.fromJson', () {
    test('reads what findAccountByEmail returns', () {
      final account = AccountToDelete.fromJson({
        'uid': 'u1',
        'name': 'Pat',
        'email': 'pat@example.com',
        'signInWith': ['google.com', 'password'],
        'createdAt': '2026-11-02T18:00:00.000Z',
        'lastSignInAt': null,
        'photos': 1,
        'messages': 2,
        'likes': 3,
      });
      expect(account.uid, 'u1');
      expect(account.signInWith, ['google.com', 'password']);
      expect(account.createdAt?.toUtc(), DateTime.utc(2026, 11, 2, 18));
      expect(account.lastSignInAt, isNull);
      expect(contentsLine(account), contains('2 comments and chat messages'));
    });
  });

  test('describes sign-in and contents in plain words', () {
    expect(signInLabel(['google.com']), 'Google');
    expect(
      signInLabel(['apple.com', 'password']),
      'Apple and email and password',
    );
    expect(signInLabel([]), 'nothing (a guest)');
    expect(
      contentsLine(const AccountToDelete(uid: 'u', photos: 1, messages: 1)),
      '1 photo, 1 comment or chat message, 0 likes',
    );
    expect(shortDate(DateTime(2026, 11, 6)), 'Nov 6, 2026');
  });

  group('DeleteAccountOfDialog', () {
    Future<void> open(
      WidgetTester tester, {
      required Future<AccountToDelete?> Function(String email) find,
      Future<void> Function(String uid)? delete,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeleteAccountOfDialog(
              find: find,
              delete: delete ?? (_) async {},
            ),
          ),
        ),
      );
    }

    testWidgets('finds the account, shows whose it is, then deletes it', (
      tester,
    ) async {
      String? searched;
      String? deleted;
      await open(
        tester,
        find: (email) async {
          searched = email;
          return _pat;
        },
        delete: (uid) async => deleted = uid,
      );

      await tester.enterText(find.byType(TextField), '  pat@example.com ');
      await tester.pump();
      await tester.tap(find.text('Find account'));
      await tester.pumpAndSettle();

      expect(searched, 'pat@example.com');
      expect(find.text('Pat'), findsOneWidget);
      expect(find.text('Signs in with Google'), findsOneWidget);
      expect(find.text('Joined Nov 2, 2026'), findsOneWidget);
      expect(deleted, isNull);

      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();

      expect(deleted, 'u1');
      expect(find.text('Account deleted'), findsOneWidget);
      expect(find.textContaining("Pat's account"), findsOneWidget);
    });

    testWidgets('says so when no account uses the address', (tester) async {
      await open(tester, find: (_) async => null);

      await tester.enterText(find.byType(TextField), 'nobody@example.com');
      await tester.pump();
      await tester.tap(find.text('Find account'));
      await tester.pumpAndSettle();

      expect(find.text('No account uses that email address.'), findsOneWidget);
      expect(find.text('Find account'), findsOneWidget);
    });

    testWidgets('shows the server refusing a moderator account', (
      tester,
    ) async {
      await open(
        tester,
        find: (_) async => _pat,
        delete: (_) async => throw FirebaseFunctionsException(
          code: 'failed-precondition',
          message: "That is a moderator's account.",
        ),
      );

      await tester.enterText(find.byType(TextField), 'pat@example.com');
      await tester.pump();
      await tester.tap(find.text('Find account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();

      expect(find.text("That is a moderator's account."), findsOneWidget);
      expect(find.text('Account deleted'), findsNothing);
    });
  });
}
