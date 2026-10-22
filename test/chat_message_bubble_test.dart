import 'package:bills_bay_area/core/models/models.dart';
import 'package:bills_bay_area/features/chat/widgets/chat_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const alice = UserProfile(
    id: 'alice',
    name: 'Alice',
    initials: 'A',
    avatarColor: Colors.green,
  );
  const message = ChatMessage(
    id: 'm1',
    user: alice,
    text: 'Great trail!',
    timestamp: 'Just now',
  );

  Widget harness(String viewerId) => MaterialApp(
    home: Scaffold(
      body: ChatMessageBubble(message: message, viewerId: viewerId),
    ),
  );

  testWidgets('another reader sees the author name and avatar', (tester) async {
    await tester.pumpWidget(harness('bob'));
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('the author sees their own message without a name', (
    tester,
  ) async {
    await tester.pumpWidget(harness('alice'));
    expect(find.text('Great trail!'), findsOneWidget);
    expect(find.text('Alice'), findsNothing);
  });
}
