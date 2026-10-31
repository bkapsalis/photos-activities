/// Photos from a picker that closes with a single photo the moment its name
/// is tapped: Android's document picker, where Google Drive is, and Google's
/// own picker on the web. Neither can be told otherwise, so instead the
/// picker is opened again after each lone photo, for the person to go on
/// choosing, until they close it or confirm several photos at once.
///
/// [pick] opens the picker: [chosen] photos are in hand so far, there is
/// room for [room] more, and [after] is the lone photo picked last (null the
/// first time). A photo picked twice counts once, matched by [idOf].
Future<List<T>> keepPicking<T>({
  required int limit,
  required Object Function(T photo) idOf,
  required Future<List<T>> Function({
    required int chosen,
    required int room,
    required T? after,
  })
  pick,
}) async {
  final picked = <T>[];
  final ids = <Object>{};
  T? after;
  while (picked.length < limit) {
    final batch = await pick(
      chosen: picked.length,
      room: limit - picked.length,
      after: after,
    );
    for (final photo in batch) {
      if (picked.length < limit && ids.add(idOf(photo))) picked.add(photo);
    }
    // Closed, or several ticked and confirmed: done either way.
    if (batch.length != 1) break;
    after = batch.single;
  }
  return picked;
}

/// What the reopened picker says, so its closing and opening again reads as
/// "added", not as a photo lost, and how to finish: [toFinish].
String keepPickingNote(int chosen, {required String toFinish}) =>
    '${chosen == 1 ? '1 photo' : '$chosen photos'} added. '
    'Pick more, or $toFinish.';
