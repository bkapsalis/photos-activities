import 'dart:async';

import 'package:bills_bay_area/core/models/models.dart';
import 'package:bills_bay_area/core/services/moderation_service.dart';
import 'package:bills_bay_area/core/services/safety_service.dart';
import 'package:bills_bay_area/core/utils/combine_latest.dart';
import 'package:bills_bay_area/core/utils/user_action.dart';
import 'package:bills_bay_area/features/chat/widgets/chat_widgets.dart';
import 'package:bills_bay_area/features/safety/report_dialog.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _sam = UserProfile(
  id: 'sam',
  name: 'Sam',
  initials: 'S',
  avatarColor: Colors.blue,
);

void main() {
  group('combineLatest', () {
    test('waits for both, then follows each', () async {
      final a = StreamController<int>();
      final b = StreamController<String>();
      final out = <String>[];
      final sub = combineLatest(
        a.stream,
        b.stream,
        (int x, String y) => '$x$y',
      ).listen(out.add);

      a.add(1);
      await pumpEventQueue();
      expect(out, isEmpty);
      b.add('a');
      a.add(2);
      b.add('b');
      await pumpEventQueue();
      expect(out, ['1a', '2a', '2b']);

      await sub.cancel();
      expect(a.hasListener, isFalse);
      expect(b.hasListener, isFalse);
    });

    test('passes errors through', () async {
      final a = StreamController<int>();
      final errors = <Object>[];
      combineLatest(
        a.stream,
        Stream.value(0),
        (int x, int y) => x + y,
      ).listen(null, onError: errors.add);

      a.addError(StateError('boom'));
      await pumpEventQueue();
      expect(errors.single, isA<StateError>());
    });
  });

  group('SafetyFilter', () {
    test('reads blocks and hidden posts as the app writes them', () {
      final filter = SafetyFilter.fromFirestore({
        'blocked': {
          'sam': {'name': 'Sam'},
          'lee': 'not a map',
        },
        'hidden': ['comments/p1/messages/c1', 42],
      });
      expect(filter.blocked, {'sam': 'Sam', 'lee': 'Someone'});
      expect(filter.hidden, {'comments/p1/messages/c1'});
    });

    test('hides blocked people\'s posts and reported posts only', () {
      const filter = SafetyFilter(
        blocked: {'sam': 'Sam'},
        hidden: {'comments/p1/messages/c1'},
      );
      expect(filter.allows('comments/p1/messages/c2', 'sam'), isFalse);
      expect(filter.allows('comments/p1/messages/c1', 'alex'), isFalse);
      expect(filter.allows('comments/p1/messages/c2', 'alex'), isTrue);
      expect(SafetyFilter.fromFirestore(null).allows('photos/p1', 'x'), isTrue);
    });
  });

  group('ReportTarget', () {
    test('points at each kind of post where the rules expect it', () {
      const comment = Comment(id: 'c1', user: _sam, text: 'hi', timestamp: '');
      const message = ChatMessage(
        id: 'm1',
        user: _sam,
        text: 'yo',
        timestamp: '',
      );
      final photo = PhotoPost(
        id: 'p1',
        imageUrl: 'https://example.com/p.jpg',
        location: const Location(
          id: '',
          name: 'Vasona Lake',
          postCount: 0,
          category: '',
        ),
        user: _sam,
        heartCount: 0,
      );

      final photoTarget = ReportTarget.photo(photo);
      expect(photoTarget.path, 'photos/p1');
      expect(photoTarget.preview, 'Vasona Lake');
      expect(photoTarget.imageUrl, 'https://example.com/p.jpg');
      expect(
        ReportTarget.comment('p1', comment).path,
        'comments/p1/messages/c1',
      );
      final chat = ReportTarget.chat('vasona_lake', message);
      expect(chat.path, 'chats/vasona_lake/messages/m1');
      expect(chat.noun, 'message');
    });
  });

  group('PostNotice', () {
    test('tells the author what was taken down and why', () {
      const notice = PostNotice(
        id: 'n1',
        kind: 'comment',
        restored: false,
        flaggedFor: ['Hate', 'Harassment'],
        preview: 'you lot',
      );
      expect(notice.title, 'Inappropriate content detected and blocked');
      expect(
        notice.message,
        'Your comment "you lot" was removed by the content filter. The AI '
        'flagged it for: hate, harassment. If you think this is a mistake, '
        'email bkapsalis@gmail.com.',
      );
    });

    test('names a photo by its place, and says when it is back', () {
      const notice = PostNotice(
        id: 'n1',
        kind: 'photo',
        restored: true,
        preview: 'Vasona Lake',
      );
      expect(notice.title, 'Your photo is back');
      expect(notice.message, startsWith('Your photo at Vasona Lake was'));
    });
  });

  group('ReportedPost.group', () {
    test('gathers every report about a post, newest post first', () {
      Map<String, dynamic> report(String path, String reason, int day) => {
        'kind': 'comment',
        'path': path,
        'authorId': 'sam',
        'authorName': 'Sam',
        'preview': 'hi',
        'reason': reason,
        'createdAt': Timestamp.fromDate(DateTime(2026, 11, day)),
      };

      final posts = ReportedPost.group([
        ('r1', report('comments/p1/messages/c1', 'hate', 1)),
        ('r2', report('comments/p1/messages/c2', 'spam', 3)),
        ('r3', report('comments/p1/messages/c1', 'hate', 2)),
        ('r4', report('comments/p1/messages/c1', 'spam', 2)),
      ]);

      expect(posts.map((post) => post.path), [
        'comments/p1/messages/c2',
        'comments/p1/messages/c1',
      ]);
      expect(posts.last.reports, hasLength(3));
      expect(
        posts.last.reasonSummary,
        'Hate speech or symbols (2), Spam or a scam',
      );
    });
  });

  group('runUserAction explain', () {
    testWidgets('shows a recognised failure in its own words', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => runUserAction(
                  context,
                  () async => throw StateError('banned'),
                  failureMessage: 'Your comment was not posted.',
                  explain: (_) async => bannedMessage,
                ),
                child: const Text('Go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      expect(find.text(bannedMessage), findsOneWidget);
      expect(find.text('Your comment was not posted.'), findsNothing);
    });
  });

  group('Report and Block in the app', () {
    testWidgets('someone else\'s chat message offers Report and Block', (
      tester,
    ) async {
      const message = ChatMessage(
        id: 'm1',
        user: _sam,
        text: 'Great trail!',
        timestamp: 'Just now',
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChatMessageBubble(
              message: message,
              viewerId: 'alex',
              locationId: 'vasona_lake',
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();

      expect(find.text('Report message'), findsOneWidget);
      expect(find.text('Block Sam'), findsOneWidget);
    });

    testWidgets('your own chat message offers neither', (tester) async {
      const message = ChatMessage(
        id: 'm1',
        user: _sam,
        text: 'Great trail!',
        timestamp: 'Just now',
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChatMessageBubble(
              message: message,
              viewerId: 'sam',
              locationId: 'vasona_lake',
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.more_horiz), findsNothing);
    });

    testWidgets('a report needs a reason before it can be sent', (
      tester,
    ) async {
      const target = ReportTarget(
        kind: 'comment',
        path: 'comments/p1/messages/c1',
        author: _sam,
        preview: 'hi',
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ReportDialog(target: target)),
        ),
      );

      FilledButton report() =>
          tester.widget(find.widgetWithText(FilledButton, 'Report'));
      expect(report().onPressed, isNull);
      expect(find.text('Also block Sam'), findsOneWidget);

      await tester.tap(find.text('Bullying or harassment'));
      await tester.pump();
      expect(report().onPressed, isNotNull);
    });
  });
}
