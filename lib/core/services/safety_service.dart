import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../config/contact.dart';
import '../models/models.dart';
import 'crash_reporting.dart';

/// Why someone reports a post. The ids are the reasons firestore.rules
/// accept.
enum ReportReason {
  sexual('sexual', 'Nudity or sexual content'),
  hate('hate', 'Hate speech or symbols'),
  violence('violence', 'Violence or threats'),
  harassment('harassment', 'Bullying or harassment'),
  spam('spam', 'Spam or a scam'),
  other('other', 'Something else');

  const ReportReason(this.id, this.label);

  final String id;
  final String label;

  static ReportReason fromId(Object? id) =>
      values.firstWhere((reason) => reason.id == id, orElse: () => other);
}

/// A post that can be reported: where it is, who wrote it, and enough of it
/// for the moderator to see what it was even if it is deleted.
class ReportTarget {
  /// 'photo', 'comment' or 'chat'.
  final String kind;

  /// Its Firestore path, such as "comments/{photoId}/messages/{id}".
  final String path;
  final UserProfile author;

  /// The words reported; for a photo, where it was taken.
  final String preview;
  final String? imageUrl;

  const ReportTarget({
    required this.kind,
    required this.path,
    required this.author,
    required this.preview,
    this.imageUrl,
  });

  factory ReportTarget.photo(PhotoPost photo) => ReportTarget(
    kind: 'photo',
    path: 'photos/${photo.id}',
    author: photo.user,
    preview: photo.location.name,
    imageUrl: photo.imageUrl,
  );

  factory ReportTarget.comment(String photoId, Comment comment) => ReportTarget(
    kind: 'comment',
    path: 'comments/$photoId/messages/${comment.id}',
    author: comment.user,
    preview: comment.text,
  );

  factory ReportTarget.chat(String locationId, ChatMessage message) =>
      ReportTarget(
        kind: 'chat',
        path: 'chats/$locationId/messages/${message.id}',
        author: message.user,
        preview: message.text,
      );

  /// What to call it in a sentence: "photo", "comment" or "message".
  String get noun => postNoun(kind);
}

/// "photo", "comment" or "message", for a post of [kind].
String postNoun(String kind) => switch (kind) {
  'photo' => 'photo',
  'comment' => 'comment',
  _ => 'message',
};

/// What the reader has asked not to see: everything by the people they
/// blocked, and each post they reported.
class SafetyFilter {
  /// Blocked people's uids, with the names they had when blocked.
  final Map<String, String> blocked;

  /// Paths of the posts they reported.
  final Set<String> hidden;

  const SafetyFilter({this.blocked = const {}, this.hidden = const {}});

  static const none = SafetyFilter();

  /// Reads userSafety/{uid}, skipping anything that is not as the app
  /// writes it.
  factory SafetyFilter.fromFirestore(Map<String, dynamic>? data) {
    final blocked = <String, String>{};
    final rawBlocked = data?['blocked'];
    if (rawBlocked is Map) {
      rawBlocked.forEach((uid, entry) {
        if (uid is! String) return;
        final name = entry is Map ? entry['name'] : null;
        blocked[uid] = name is String && name.isNotEmpty ? name : 'Someone';
      });
    }
    final rawHidden = data?['hidden'];
    return SafetyFilter(
      blocked: blocked,
      hidden: rawHidden is List ? rawHidden.whereType<String>().toSet() : {},
    );
  }

  bool allows(String path, String authorId) =>
      !hidden.contains(path) && !blocked.containsKey(authorId);

  bool allowsPhoto(PhotoPost photo) =>
      allows('photos/${photo.id}', photo.user.id);
}

/// A notice that a post of the reader's was taken down by the content
/// filter, or later put back by a moderator.
class PostNotice {
  final String id;
  final String kind;
  final bool restored;
  final List<String> flaggedFor;
  final String preview;

  const PostNotice({
    required this.id,
    required this.kind,
    required this.restored,
    this.flaggedFor = const [],
    this.preview = '',
  });

  factory PostNotice.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final flagged = data['flaggedFor'];
    return PostNotice(
      id: doc.id,
      kind: data['kind'] as String? ?? 'comment',
      restored: data['restored'] == true,
      flaggedFor: flagged is List ? flagged.whereType<String>().toList() : [],
      preview: data['preview'] as String? ?? '',
    );
  }

  String get title => restored
      ? 'Your ${postNoun(kind)} is back'
      : 'Inappropriate content detected and blocked';

  String get message {
    final noun = postNoun(kind);
    final which = preview.isEmpty
        ? 'Your $noun'
        : kind == 'photo'
        ? 'Your photo at $preview'
        : 'Your $noun "$preview"';
    if (restored) {
      return '$which was reviewed by a moderator and put back. Sorry for '
          'the mix-up.';
    }
    final why = flaggedFor.isEmpty
        ? ''
        : ' The AI flagged it for: ${flaggedFor.join(', ').toLowerCase()}.';
    return '$which was removed by the content filter.$why If you think '
        'this is a mistake, email $contactEmail.';
  }
}

/// Reporting, blocking and the rest of what keeps the app pleasant, for
/// everyone signed in. The moderator's side is ModerationService.
class SafetyService {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  SafetyService({FirebaseFirestore? db, FirebaseAuth? auth})
    : _db = db ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  DocumentReference<Map<String, dynamic>> _mine(String uid) =>
      _db.collection('userSafety').doc(uid);

  String _uid() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Not signed in.');
    return uid;
  }

  /// The reader's filter, live. If it cannot be read, everything is shown
  /// rather than nothing: a failure here must not empty the app.
  Stream<SafetyFilter> filter() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(SafetyFilter.none);
    return _mine(uid).snapshots().transform(
      StreamTransformer.fromHandlers(
        handleData: (snapshot, sink) =>
            sink.add(SafetyFilter.fromFirestore(snapshot.data())),
        handleError: (error, stack, sink) {
          CrashReporting.recordError(
            error,
            stack,
            reason: 'reading blocks and hidden posts',
          );
          sink.add(SafetyFilter.none);
        },
      ),
    );
  }

  /// Sends [target] to the moderators, and hides it from the reader at once.
  Future<void> report(
    ReportTarget target,
    ReportReason reason, {
    String details = '',
  }) async {
    final uid = _uid();
    final batch = _db.batch()
      ..set(_db.collection('reports').doc(), {
        'reporterId': uid,
        'kind': target.kind,
        'path': target.path,
        'authorId': target.author.id,
        'authorName': _clip(target.author.name, 80),
        'preview': _clip(target.preview, 2000),
        'imageUrl': target.imageUrl,
        'reason': reason.id,
        if (details.trim().isNotEmpty) 'details': _clip(details.trim(), 500),
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'open',
      })
      ..set(_mine(uid), {
        'hidden': FieldValue.arrayUnion([target.path]),
      }, SetOptions(merge: true));
    await batch.commit();
  }

  /// Hides everything [user] posts from the reader, now and later.
  Future<void> block(UserProfile user) => _mine(_uid()).set({
    'blocked': {
      user.id: {'name': user.name, 'at': FieldValue.serverTimestamp()},
    },
  }, SetOptions(merge: true));

  Future<void> unblock(String userId) => _mine(_uid()).update({
    FieldPath(['blocked', userId]): FieldValue.delete(),
  });

  /// Whether a moderator has banned the reader. False when it cannot tell:
  /// the rules refuse a banned person's post anyway.
  Future<bool> isBanned() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    try {
      return (await _db.collection('bannedUsers').doc(uid).get()).exists;
    } catch (_) {
      return false;
    }
  }

  /// The reader's notices not yet shown.
  Stream<List<PostNotice>> unseenNotices() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(const []);
    return _db
        .collection('users')
        .doc(uid)
        .collection('notices')
        .where('seen', isEqualTo: false)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map(PostNotice.fromFirestore).toList(),
        );
  }

  Future<void> markSeen(String noticeId) => _db
      .collection('users')
      .doc(_uid())
      .collection('notices')
      .doc(noticeId)
      .update({'seen': true});
}

/// For runUserAction's explain: [bannedMessage] when a post was refused
/// because the reader is banned.
Future<String?> explainBan(Object error) async {
  if (error is FirebaseException &&
      error.code == 'permission-denied' &&
      await SafetyService().isBanned()) {
    return bannedMessage;
  }
  return null;
}

/// What a banned person is told when they try to post.
const bannedMessage =
    'Your account can no longer post: a moderator suspended it for breaking '
    'the community rules. To ask about it, email $contactEmail.';

String _clip(String text, int max) =>
    text.length <= max ? text : '${text.substring(0, max - 1)}…';
