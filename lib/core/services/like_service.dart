import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'analytics_service.dart';
import 'crash_reporting.dart';

/// One like per person per photo.
///
/// A like is a document at photos/{photoId}/likes/{uid}, written in the same
/// batch that moves the photo's heartCount by one. firestore.rules refuse a
/// count change without its like document appearing or going, so nobody can
/// like a photo twice or add likes for anyone else. The count itself stays
/// on the photo, so the feed can sort by popularity without counting.
class LikeService {
  LikeService._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static ValueNotifier<Set<String>>? _liked;

  /// Ids of the photos the signed-in reader has liked, kept current. One
  /// shared listener, however many hearts are on screen, restarted whenever
  /// someone else signs in.
  static ValueListenable<Set<String>> get likedPhotoIds {
    final existing = _liked;
    if (existing != null) return existing;

    final liked = _liked = ValueNotifier(const <String>{});
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? likes;
    FirebaseAuth.instance.authStateChanges().listen((user) {
      likes?.cancel();
      liked.value = const {};
      if (user == null) return;
      likes = _db
          .collectionGroup('likes')
          .where('userId', isEqualTo: user.uid)
          .snapshots()
          .listen(
            (snapshot) => liked.value = {
              for (final doc in snapshot.docs)
                if (doc.reference.parent.parent case final photo?) photo.id,
            },
            onError: (Object error, StackTrace stack) =>
                CrashReporting.recordError(
                  error,
                  stack,
                  reason: 'liked photos could not be loaded',
                ),
          );
    });
    return liked;
  }

  /// Likes or unlikes [photoId] as the signed-in reader. Throws if it did
  /// not happen.
  static Future<void> setLiked(String photoId, {required bool liked}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Not signed in');

    final photo = _db.collection('photos').doc(photoId);
    final like = photo.collection('likes').doc(uid);
    final batch = _db.batch();
    if (liked) {
      batch.set(like, {
        'userId': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      batch.delete(like);
    }
    batch.update(photo, {'heartCount': FieldValue.increment(liked ? 1 : -1)});
    await batch.commit();
    if (liked) AnalyticsService.photoLiked(photoId);
  }
}
