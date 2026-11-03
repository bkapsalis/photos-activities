import 'package:bills_bay_area/features/picture_chat/picture_chat_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('webModalSplit', () {
    // A large desktop window: the modal caps at 1400 x 820.
    const maxWidth = 1400.0, height = 820.0;
    const photoArea = height - 110; // minus the user bar and directions

    test('a portrait photo gets exactly its width, no side bars', () {
      final s = webModalSplit(
        maxWidth: maxWidth,
        height: height,
        aspectRatio: 3 / 4,
      );
      expect(s.photoWidth, closeTo(photoArea * 3 / 4, 0.01));
      // Room to spare goes to the chat, up to its cap; the modal shrinks.
      expect(s.chatWidth, 460);
      expect(s.photoWidth + 1 + s.chatWidth, lessThan(maxWidth));
    });

    test('a wide photo takes the room and the chat sits at its minimum', () {
      final s = webModalSplit(
        maxWidth: maxWidth,
        height: height,
        aspectRatio: 16 / 9,
      );
      expect(s.chatWidth, 340);
      expect(s.photoWidth + 1 + s.chatWidth, closeTo(maxWidth, 0.01));
    });

    test('a narrow window still fits, the chat taking at most half', () {
      // 600px is where this layout starts; the modal is 85% of it.
      const narrow = 510.0;
      for (final aspect in [0.5, 1.0, 2.0]) {
        final s = webModalSplit(
          maxWidth: narrow,
          height: 400,
          aspectRatio: aspect,
        );
        expect(s.photoWidth + 1 + s.chatWidth, lessThanOrEqualTo(narrow));
        expect(s.chatWidth, lessThanOrEqualTo((narrow - 1) / 2));
        expect(s.photoWidth, greaterThan(0));
      }
    });

    test('a missing or bad aspect ratio is treated as square', () {
      final square = webModalSplit(
        maxWidth: maxWidth,
        height: height,
        aspectRatio: 1,
      );
      for (final bad in [0.0, -1.0, double.nan, double.infinity]) {
        final s = webModalSplit(
          maxWidth: maxWidth,
          height: height,
          aspectRatio: bad,
        );
        expect(s.photoWidth, square.photoWidth);
        expect(s.chatWidth, square.chatWidth);
      }
    });
  });
}
