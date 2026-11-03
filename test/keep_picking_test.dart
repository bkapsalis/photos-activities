import 'package:bills_bay_area/core/services/keep_picking.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Picks from a picker that answers each opening with the next of
  /// [rounds], and notes how it was opened each time: "chosen/room/after".
  Future<({List<String> picked, List<String> opened})> run(
    List<List<String>> rounds, {
    int limit = 10,
  }) async {
    final opened = <String>[];
    var round = 0;
    final picked = await keepPicking<String>(
      limit: limit,
      idOf: (photo) => photo,
      pick: ({required chosen, required room, required after}) async {
        opened.add('$chosen/$room/$after');
        return round < rounds.length ? rounds[round++] : const [];
      },
    );
    return (picked: picked, opened: opened);
  }

  test('a photo picked alone opens the picker again, after it, until it is '
      'closed', () async {
    final result = await run([
      ['a'],
      ['b'],
      [],
    ]);

    expect(result.picked, ['a', 'b']);
    expect(result.opened, ['0/10/null', '1/9/a', '2/8/b']);
  });

  test('several photos confirmed at once end the picking', () async {
    final result = await run([
      ['a'],
      ['b', 'c'],
    ]);

    expect(result.picked, ['a', 'b', 'c']);
    expect(result.opened, hasLength(2));
  });

  test('closing the picker at once picks nothing', () async {
    final result = await run([]);

    expect(result.picked, isEmpty);
    expect(result.opened, hasLength(1));
  });

  test('a photo picked twice counts once', () async {
    final result = await run([
      ['a'],
      ['a'],
      [],
    ]);

    expect(result.picked, ['a']);
  });

  test('picking stops at the limit', () async {
    final result = await run([
      ['a'],
      ['b'],
      ['c'],
    ], limit: 2);

    expect(result.picked, ['a', 'b']);
    expect(result.opened, hasLength(2));
  });

  test('the reopened picker says what was added and how to finish', () {
    expect(
      keepPickingNote(1, toFinish: 'press Back until this closes'),
      '1 photo added. Pick more, or press Back until this closes.',
    );
    expect(
      keepPickingNote(3, toFinish: 'Cancel'),
      '3 photos added. Pick more, or Cancel.',
    );
  });
}
