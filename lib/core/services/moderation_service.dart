import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'firestore_service.dart';
import 'photo_deletion_service.dart';
import 'safety_service.dart';

/// One report, as SafetyService.report wrote it.
class Report {
  final String id;
  final ReportReason reason;
  final String details;
  final DateTime? createdAt;

  const Report({
    required this.id,
    required this.reason,
    this.details = '',
    this.createdAt,
  });
}

/// A post with open reports against it: every report about it together, so
/// the moderator deals with each post once.
class ReportedPost {
  final String kind;
  final String path;
  final String authorId;
  final String authorName;
  final String preview;
  final String? imageUrl;
  final List<Report> reports;

  const ReportedPost({
    required this.kind,
    required this.path,
    required this.authorId,
    required this.authorName,
    required this.preview,
    this.imageUrl,
    required this.reports,
  });

  DateTime? get latest => reports
      .map((report) => report.createdAt)
      .whereType<DateTime>()
      .fold<DateTime?>(
        null,
        (latest, at) => latest == null || at.isAfter(latest) ? at : latest,
      );

  /// Each reason given, with how many gave it, most given first: "Hate
  /// speech or symbols (2), Spam or a scam".
  String get reasonSummary {
    final counts = <ReportReason, int>{};
    for (final report in reports) {
      counts[report.reason] = (counts[report.reason] ?? 0) + 1;
    }
    final ordered = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ordered
        .map((e) => e.value > 1 ? '${e.key.label} (${e.value})' : e.key.label)
        .join(', ');
  }

  /// Groups open reports, given as (id, data) pairs, by the post they are
  /// about, most recent first.
  static List<ReportedPost> group(
    Iterable<(String id, Map<String, dynamic> data)> reports,
  ) {
    final byPath = <String, List<(String, Map<String, dynamic>)>>{};
    for (final report in reports) {
      final path = report.$2['path'];
      if (path is String) byPath.putIfAbsent(path, () => []).add(report);
    }
    final posts = byPath.entries.map((entry) {
      final first = entry.value.first.$2;
      return ReportedPost(
        kind: first['kind'] as String? ?? 'comment',
        path: entry.key,
        authorId: first['authorId'] as String? ?? '',
        authorName: first['authorName'] as String? ?? 'Someone',
        preview: first['preview'] as String? ?? '',
        imageUrl: first['imageUrl'] as String?,
        reports: entry.value
            .map(
              (report) => Report(
                id: report.$1,
                reason: ReportReason.fromId(report.$2['reason']),
                details: report.$2['details'] as String? ?? '',
                createdAt: (report.$2['createdAt'] as Timestamp?)?.toDate(),
              ),
            )
            .toList(),
      );
    }).toList();
    posts.sort(
      (a, b) => (b.latest ?? DateTime(0)).compareTo(a.latest ?? DateTime(0)),
    );
    return posts;
  }
}

/// A post the AI content filter took down (blockedContent/{key}).
class RemovedPost {
  final String key;
  final String kind;
  final String authorId;
  final String authorName;
  final List<String> flaggedFor;
  final String reason;
  final String text;
  final String? imageUrl;
  final String place;
  final DateTime? removedAt;

  const RemovedPost({
    required this.key,
    required this.kind,
    required this.authorId,
    required this.authorName,
    this.flaggedFor = const [],
    this.reason = '',
    this.text = '',
    this.imageUrl,
    this.place = '',
    this.removedAt,
  });

  factory RemovedPost.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final post = data['data'] as Map<String, dynamic>? ?? {};
    final flagged = data['flaggedFor'];
    return RemovedPost(
      key: doc.id,
      kind: data['kind'] as String? ?? 'comment',
      authorId: data['authorId'] as String? ?? '',
      authorName: data['authorName'] as String? ?? 'Someone',
      flaggedFor: flagged is List ? flagged.whereType<String>().toList() : [],
      reason: data['reason'] as String? ?? '',
      text: post['text'] as String? ?? '',
      imageUrl: post['imageUrl'] as String?,
      place: post['locationName'] as String? ?? '',
      removedAt: (data['removedAt'] as Timestamp?)?.toDate(),
    );
  }
}

class BannedUser {
  final String id;
  final String name;
  final DateTime? bannedAt;

  const BannedUser({required this.id, required this.name, this.bannedAt});
}

/// Someone's account as findAccountByEmail describes it, for the moderator
/// to check it is the right one before deleting it.
class AccountToDelete {
  final String uid;
  final String? name;
  final String? email;

  /// How they sign in: "google.com", "apple.com" or "password".
  final List<String> signInWith;
  final DateTime? createdAt;
  final DateTime? lastSignInAt;
  final int photos;

  /// Comments and chat messages.
  final int messages;
  final int likes;

  const AccountToDelete({
    required this.uid,
    this.name,
    this.email,
    this.signInWith = const [],
    this.createdAt,
    this.lastSignInAt,
    this.photos = 0,
    this.messages = 0,
    this.likes = 0,
  });

  factory AccountToDelete.fromJson(Object? json) {
    final map = json is Map ? json : const {};
    int count(String key) => (map[key] as num?)?.toInt() ?? 0;
    DateTime? date(String key) =>
        DateTime.tryParse(map[key] as String? ?? '')?.toLocal();
    return AccountToDelete(
      uid: map['uid'] as String? ?? '',
      name: map['name'] as String?,
      email: map['email'] as String?,
      signInWith: [
        for (final provider in map['signInWith'] as List? ?? const [])
          '$provider',
      ],
      createdAt: date('createdAt'),
      lastSignInAt: date('lastSignInAt'),
      photos: count('photos'),
      messages: count('messages'),
      likes: count('likes'),
    );
  }
}

/// The moderator's tools: reports, bans, what the content filter took
/// down, the filter's switch, and deleting someone's account for them.
/// firestore.rules, and the functions, let only a moderator use any of it.
class ModerationService {
  final FirebaseFirestore _db;

  ModerationService({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  // Where the functions are deployed: REGION in functions/src/config.ts.
  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'us-west1');

  // ── Reports ────────────────────────────────────────

  Stream<List<ReportedPost>> openReports() => _db
      .collection('reports')
      .where('status', isEqualTo: 'open')
      .snapshots()
      .map(
        (snapshot) => ReportedPost.group(
          snapshot.docs.map((doc) => (doc.id, doc.data())),
        ),
      );

  /// Closes every report about [post] as [resolution]: 'deleted' or
  /// 'dismissed'.
  Future<void> settle(ReportedPost post, String resolution) async {
    final batch = _db.batch();
    for (final report in post.reports) {
      batch.update(_db.collection('reports').doc(report.id), {
        'status': resolution,
        'settledAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  /// Deletes the reported post, if it is still there, and closes its
  /// reports.
  Future<void> deleteReported(ReportedPost post) async {
    final segments = post.path.split('/');
    switch (post.kind) {
      case 'photo':
        final result = await PhotoDeletionService().deleteOne(
          photoId: segments[1],
          imageUrl: post.imageUrl ?? '',
        );
        if (result.failed > 0) throw StateError('Could not delete the photo.');
      case 'comment':
        // Uncounting a comment that is already gone would make the photo's
        // count wrong.
        if ((await _db.doc(post.path).get()).exists) {
          await FirestoreService().deleteComment(segments[1], segments[3]);
        }
      default:
        await _db.doc(post.path).delete();
    }
    await settle(post, 'deleted');
  }

  // ── Bans ───────────────────────────────────────────

  Future<void> ban(String userId, String name) => _db
      .collection('bannedUsers')
      .doc(userId)
      .set({'name': name, 'bannedAt': FieldValue.serverTimestamp()});

  Future<void> unban(String userId) =>
      _db.collection('bannedUsers').doc(userId).delete();

  Stream<List<BannedUser>> bannedUsers() => _db
      .collection('bannedUsers')
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map(
              (doc) => BannedUser(
                id: doc.id,
                name: doc.data()['name'] as String? ?? 'Someone',
                bannedAt: (doc.data()['bannedAt'] as Timestamp?)?.toDate(),
              ),
            )
            .toList(),
      );

  // ── The content filter ─────────────────────────────

  Stream<bool> contentFilterOn() => _db
      .doc('config/app')
      .snapshots()
      .map((snapshot) => snapshot.data()?['contentFilter'] == true);

  Future<void> setContentFilter(bool on) =>
      _db.doc('config/app').set({'contentFilter': on}, SetOptions(merge: true));

  /// What the filter took down and nobody has put back, newest first.
  Stream<List<RemovedPost>> removedPosts() => _db
      .collection('blockedContent')
      .where('status', isEqualTo: 'removed')
      .snapshots()
      .map((snapshot) {
        final posts = snapshot.docs.map(RemovedPost.fromFirestore).toList();
        posts.sort(
          (a, b) => (b.removedAt ?? DateTime(0)).compareTo(
            a.removedAt ?? DateTime(0),
          ),
        );
        return posts;
      });

  /// Puts a removed post back where it was, and tells its author.
  Future<void> restore(String key) => _functions
      .httpsCallable('restoreRemovedPost')
      .call<Object?>({'key': key});

  /// Deletes a removed post for good, a photo's image file with it.
  Future<void> discard(String key) => _functions
      .httpsCallable('discardRemovedPost')
      .call<Object?>({'key': key});

  // ── Deleting someone's account ─────────────────────
  // For someone who emails to ask, as web/delete-account.html offers.

  /// The account signed up with [email], or null when no account uses it.
  Future<AccountToDelete?> findAccount(String email) async {
    try {
      final result = await _functions
          .httpsCallable('findAccountByEmail')
          .call<Object?>({'email': email.trim()});
      return AccountToDelete.fromJson(result.data);
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'not-found') return null;
      rethrow;
    }
  }

  /// Deletes the account and everything in it, as its owner's own
  /// "Delete account" would.
  Future<void> deleteAccountOf(String uid) => _functions
      .httpsCallable(
        'deleteAccountOf',
        // Someone who posted a great deal takes a while to clear.
        options: HttpsCallableOptions(timeout: const Duration(minutes: 5)),
      )
      .call<Object?>({'uid': uid});
}
