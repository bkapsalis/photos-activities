import 'package:cloud_firestore/cloud_firestore.dart';

import 'crash_reporting.dart';

/// What one person has added to the community.
///
/// Every field is nullable: a figure that could not be read is shown as "—"
/// rather than as a zero, which would understate someone's contribution.
class ContributionStats {
  final int? photos;
  final int? likesReceived;
  final int? comments;

  const ContributionStats({this.photos, this.likesReceived, this.comments});

  /// True once at least one figure is known and non-zero.
  bool get hasAny =>
      (photos ?? 0) > 0 || (likesReceived ?? 0) > 0 || (comments ?? 0) > 0;
}

class ContributionStatsService {
  final FirebaseFirestore _db;

  ContributionStatsService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  Future<ContributionStats> forUser(String userId) async {
    final photos = await _photoStats(userId);
    return ContributionStats(
      photos: photos?.count,
      likesReceived: photos?.likes,
      comments: await _commentCount(userId),
    );
  }

  /// Photo count and the likes those photos have collected.
  ///
  /// Both come from one read: hearts live on the photo document, so summing
  /// them costs nothing beyond the query already needed for the count.
  Future<({int count, int likes})?> _photoStats(String userId) async {
    try {
      final snapshot = await _db
          .collection('photos')
          .where('userId', isEqualTo: userId)
          .get();

      var likes = 0;
      for (final doc in snapshot.docs) {
        likes += (doc.data()['heartCount'] as num?)?.toInt() ?? 0;
      }
      return (count: snapshot.docs.length, likes: likes);
    } catch (e, stack) {
      CrashReporting.recordError(
        e,
        stack,
        reason: 'ContributionStatsService._photoStats failed',
      );
      return null;
    }
  }

  /// Comments this person has written on other people's photos.
  ///
  /// Location chat and picture comments share the "messages" collection group,
  /// and a query cannot filter on the parent path — so the split is made from
  /// each document's own path.
  Future<int?> _commentCount(String userId) async {
    try {
      final snapshot = await _db
          .collectionGroup('messages')
          .where('userId', isEqualTo: userId)
          .get();

      return snapshot.docs
          .where((doc) => doc.reference.path.startsWith('comments/'))
          .length;
    } catch (e, stack) {
      CrashReporting.recordError(
        e,
        stack,
        reason: 'ContributionStatsService._commentCount failed',
      );
      return null;
    }
  }
}
