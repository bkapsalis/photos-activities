import '../models/models.dart';

extension PhotoPostSorting on List<PhotoPost> {
  /// Most-liked photos first, newest first among photos with equal hearts.
  ///
  /// Returns a new list; the receiver is left untouched so a list coming
  /// straight off a stream is never mutated in place.
  List<PhotoPost> sortedByPopularity() {
    final sorted = List<PhotoPost>.of(this);
    sorted.sort((a, b) {
      final byHearts = b.heartCount.compareTo(a.heartCount);
      if (byHearts != 0) return byHearts;

      // Undated photos sink below dated ones rather than jumping the queue.
      final aDate = a.createdAt;
      final bDate = b.createdAt;
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return bDate.compareTo(aDate);
    });
    return sorted;
  }
}
