import 'package:bills_bay_area/core/models/models.dart';
import 'package:bills_bay_area/core/services/ai_service.dart';
import 'package:bills_bay_area/core/theme/app_colors.dart';
import 'package:bills_bay_area/features/picture_chat/ai_widgets.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _ai = UserProfile(
  id: aiNaturalistId,
  name: 'AI Naturalist',
  initials: 'AI',
  avatarColor: AppColors.ai,
);

const _heron = AiAnimal(
  commonName: 'Great Blue Heron',
  scientificName: 'Ardea herodias',
  confidence: 'high',
  description: 'A tall grey-blue wading bird.',
);

Comment _comment({AiAnimal? animal = _heron, String text = 'plain text'}) =>
    Comment(
      id: 'c1',
      user: _ai,
      text: text,
      timestamp: '2h ago',
      isAi: true,
      animal: animal,
    );

Future<void> _pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

void main() {
  group('AiAnimal.fromFirestore', () {
    test('reads an animal as the server writes it', () {
      final animal = AiAnimal.fromFirestore({
        'commonName': 'Great Blue Heron',
        'scientificName': 'Ardea herodias',
        'confidence': 'medium',
        'description': 'A tall bird.',
      });
      expect(animal?.commonName, 'Great Blue Heron');
      expect(animal?.scientificName, 'Ardea herodias');
      expect(animal?.isUncertain, isFalse);
    });

    test('is null without a name or description', () {
      expect(AiAnimal.fromFirestore(null), isNull);
      expect(AiAnimal.fromFirestore('heron'), isNull);
      expect(AiAnimal.fromFirestore({'description': 'x'}), isNull);
      expect(AiAnimal.fromFirestore({'commonName': 'Heron'}), isNull);
    });

    test('an unknown confidence counts as uncertain', () {
      final animal = AiAnimal.fromFirestore({
        'commonName': 'Gull',
        'description': 'A gull.',
        'confidence': 42,
      });
      expect(animal?.isUncertain, isTrue);
      expect(animal?.scientificName, '');
    });
  });

  group('AnimalInfoOutcome', () {
    test('says what was added', () {
      expect(
        AnimalInfoOutcome.fromJson({
          'status': 'posted',
          'count': 2,
          'names': ['Great Blue Heron', 'Mallard'],
        }).message,
        'Added 2 AI comments: Great Blue Heron, Mallard.',
      );
      expect(
        AnimalInfoOutcome.fromJson({
          'status': 'posted',
          'count': 1,
          'names': ['Mallard'],
        }).message,
        'Added an AI comment about the Mallard.',
      );
    });

    test('says when there was nothing to add', () {
      expect(
        AnimalInfoOutcome.fromJson({'status': 'noAnimals', 'count': 0}).message,
        'The AI found no animals in this photo.',
      );
      expect(
        AnimalInfoOutcome.fromJson({
          'status': 'alreadyPosted',
          'count': 3,
        }).message,
        "This photo's animals are already in the comments. Delete one to "
        'have the AI look again.',
      );
      expect(
        AnimalInfoOutcome.fromJson({
          'status': 'alreadyPosted',
          'count': 0,
        }).message,
        'Already checked: the AI found no animals in this photo.',
      );
    });

    test('copes with an answer it does not recognise', () {
      final outcome = AnimalInfoOutcome.fromJson('nonsense');
      expect(outcome.status, AnimalInfoStatus.noAnimals);
      expect(outcome.count, 0);
    });
  });

  group('AnimalBatchProgress', () {
    AnimalBatchProgress batch({
      int checked = 12,
      int failed = 0,
      int remaining = 30,
    }) => AnimalBatchProgress.fromJson({
      'checked': checked,
      'commentsAdded': 5,
      'failed': failed,
      'remaining': remaining,
      'failedTotal': failed,
    });

    test('carries on while photos remain', () {
      expect(batch().isFinished, isFalse);
      expect(batch(failed: 3).isFinished, isFalse);
    });

    test('stops when none remain, or a batch got nowhere', () {
      expect(batch(remaining: 0).isFinished, isTrue);
      expect(batch(checked: 0).isFinished, isTrue);
      expect(batch(checked: 12, failed: 12).isFinished, isTrue);
    });
  });

  group('aiErrorMessage', () {
    test('passes on what the functions said', () {
      expect(
        aiErrorMessage(
          FirebaseFunctionsException(
            code: 'failed-precondition',
            message: 'The image is too large to send.',
          ),
        ),
        'The image is too large to send.',
      );
    });

    test('hides bare statuses and unexpected errors', () {
      const fallback =
          'The AI could not look at this just now. Please try again.';
      expect(
        aiErrorMessage(
          FirebaseFunctionsException(code: 'not-found', message: 'NOT_FOUND'),
        ),
        fallback,
      );
      expect(
        aiErrorMessage(
          FirebaseFunctionsException(code: 'internal', message: 'boom'),
        ),
        fallback,
      );
      expect(aiErrorMessage(StateError('x')), fallback);
    });
  });

  group('AiCommentTile', () {
    testWidgets('shows the animal, an AI badge and a caution', (tester) async {
      await _pump(tester, AiCommentTile(comment: _comment()));

      expect(find.text('AI Naturalist'), findsOneWidget);
      expect(find.text('AI'), findsOneWidget);
      expect(
        find.textContaining('Great Blue Heron', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Ardea herodias', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('A tall grey-blue wading bird.'), findsOneWidget);
      expect(find.text('2h ago · AI-generated, may be wrong'), findsOneWidget);
      // No moderator: no menu.
      expect(find.byIcon(Icons.more_horiz), findsNothing);
    });

    testWidgets('hedges an uncertain identification', (tester) async {
      await _pump(
        tester,
        AiCommentTile(
          comment: _comment(
            animal: const AiAnimal(
              commonName: 'Gull',
              scientificName: 'Larus sp.',
              confidence: 'low',
              description: 'A gull.',
            ),
          ),
        ),
      );
      expect(
        find.textContaining('Possibly Gull', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('falls back to the text without an animal', (tester) async {
      await _pump(tester, AiCommentTile(comment: _comment(animal: null)));
      expect(find.text('plain text'), findsOneWidget);
    });

    testWidgets('offers a moderator only Delete', (tester) async {
      var deleted = false;
      await _pump(
        tester,
        AiCommentTile(comment: _comment(), onDelete: () => deleted = true),
      );

      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      expect(find.text('Edit Comment'), findsNothing);
      await tester.tap(find.text('Delete Comment'));
      await tester.pumpAndSettle();

      expect(deleted, isTrue);
    });
  });
}
