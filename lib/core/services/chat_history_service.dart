import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/models.dart';

/// Keeps a guest's chat history readable after they register.
///
/// Linking a credential preserves the Firebase uid, so ownership of past
/// messages never moves. What linking cannot fix is the denormalized author
/// name stored on each message document: without this rewrite, a new
/// registrant's old messages keep reading "Guest 4f2a".
class ChatHistoryService {
  final FirebaseFirestore _db;

  ChatHistoryService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  /// Firestore rejects batches larger than 500 writes.
  static const int _batchSize = 400;

  /// Counts the messages and comments written by [userId].
  ///
  /// Returns null when the count cannot be taken, so callers can stay quiet
  /// rather than promising to save history they could not see.
  Future<int?> countAuthoredMessages(String userId) async {
    try {
      final snapshot = await _authoredBy(userId).count().get();
      return snapshot.count;
    } catch (e) {
      debugPrint('ChatHistoryService.countAuthoredMessages failed: $e');
      return null;
    }
  }

  /// Rewrites the stored author fields on everything [profile] has written.
  ///
  /// Returns the number of documents rewritten, or null if the rewrite could
  /// not run — a missing collection-group index or a rules denial must never
  /// block registration, which has already succeeded by this point.
  Future<int?> renameAuthor(UserProfile profile) async {
    try {
      final snapshot = await _authoredBy(profile.id).get();
      final docs = snapshot.docs;
      if (docs.isEmpty) return 0;

      for (var start = 0; start < docs.length; start += _batchSize) {
        final end = min(start + _batchSize, docs.length);
        final batch = _db.batch();
        for (final doc in docs.sublist(start, end)) {
          batch.update(doc.reference, {
            'userName': profile.name,
            'userInitials': profile.initials,
            'userAvatarColor': profile.avatarColor.toARGB32(),
          });
        }
        await batch.commit();
      }
      return docs.length;
    } catch (e) {
      debugPrint('ChatHistoryService.renameAuthor failed: $e');
      return null;
    }
  }

  /// Location chat lives at chats/{id}/messages and picture comments at
  /// comments/{id}/messages, so one collection-group query covers both.
  Query<Map<String, dynamic>> _authoredBy(String userId) => _db
      .collectionGroup('messages')
      .where('userId', isEqualTo: userId);
}
