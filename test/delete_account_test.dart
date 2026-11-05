import 'package:bills_bay_area/core/services/auth_service.dart';
import 'package:bills_bay_area/features/profile/delete_account_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthService.confirmMethodFor', () {
    ConfirmMethod? methodFor(List<String> providers, {bool guest = false}) =>
        AuthService.confirmMethodFor(
          isAnonymous: guest,
          providerIds: providers,
        );

    test('asks a guest for nothing, having nothing to sign in with', () {
      expect(methodFor([], guest: true), isNull);
    });

    test('uses the sign-in method the account has', () {
      expect(methodFor(['google.com']), ConfirmMethod.google);
      expect(methodFor(['apple.com']), ConfirmMethod.apple);
      expect(methodFor(['password']), ConfirmMethod.password);
    });

    test('prefers a button to typing a password', () {
      expect(methodFor(['password', 'google.com']), ConfirmMethod.google);
      expect(methodFor(['password', 'apple.com']), ConfirmMethod.apple);
    });
  });

  group('DeleteAccountDialog', () {
    /// Opens the dialog from a button and records what it closes with.
    Future<List<bool?>> open(
      WidgetTester tester, {
      ConfirmMethod? method,
      bool isModerator = false,
      Future<String?> Function(String password)? delete,
    }) async {
      final closedWith = <bool?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => closedWith.add(
                  await showDialog<bool>(
                    context: context,
                    builder: (_) => DeleteAccountDialog(
                      method: method,
                      isModerator: isModerator,
                      delete: delete ?? (_) async => null,
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      return closedWith;
    }

    FilledButton deleteButton(WidgetTester tester) =>
        tester.widget(find.widgetWithText(FilledButton, 'Delete account'));

    testWidgets('says what goes, and closes once it is deleted', (
      tester,
    ) async {
      final closedWith = await open(tester, method: ConfirmMethod.google);

      expect(find.textContaining('cannot be undone'), findsOneWidget);
      expect(find.textContaining('sign in with Google once more'), findsOne);
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      expect(closedWith, [true]);
    });

    testWidgets('needs the password before a password account can go', (
      tester,
    ) async {
      String? sent;
      await open(
        tester,
        method: ConfirmMethod.password,
        delete: (password) async {
          sent = password;
          return null;
        },
      );

      expect(deleteButton(tester).onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'hunter22');
      await tester.pump();
      expect(deleteButton(tester).onPressed, isNotNull);

      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      expect(sent, 'hunter22');
    });

    testWidgets('stays open and says why when it does not go through', (
      tester,
    ) async {
      final closedWith = await open(
        tester,
        method: ConfirmMethod.password,
        delete: (_) async => 'That password is not right. Please try again.',
      );

      await tester.enterText(find.byType(TextField), 'wrong');
      await tester.pump();
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();

      expect(
        find.text('That password is not right. Please try again.'),
        findsOneWidget,
      );
      expect(closedWith, isEmpty);
      expect(deleteButton(tester).onPressed, isNotNull);
    });

    testWidgets("keeps the moderator's account", (tester) async {
      final closedWith = await open(
        tester,
        method: ConfirmMethod.google,
        isModerator: true,
      );

      expect(find.textContaining("moderator's account"), findsOneWidget);
      expect(find.text('Delete account'), findsOneWidget); // The title.
      expect(find.byType(FilledButton), findsNothing);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(closedWith, [false]);
    });
  });
}
