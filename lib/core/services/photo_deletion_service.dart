import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'crash_reporting.dart';

/// What a bulk delete actually managed to remove.
///
/// A delete that half-worked is worse than one that failed outright, because
/// the leftovers are invisible, so every part is counted separately rather
/// than collapsed into a single "done".
@immutable
class BulkDeleteResult {
  /// Photo documents removed. This is the number the reader cares about.
  final int photosDeleted;

  /// Storage objects removed. Lower than [photosDeleted] when a file was
  /// already missing, which is normal for photos deleted before this service
  /// existed — the old path removed the document and left the file.
  final int filesDeleted;

  /// Comment documents removed along with their photos.
  final int commentsDeleted;

  /// Photos whose document could not be removed.
  final int failed;

  const BulkDeleteResult({
    this.photosDeleted = 0,
    this.filesDeleted = 0,
    this.commentsDeleted = 0,
    this.failed = 0,
  });

  bool get isEmpty => photosDeleted == 0 && failed == 0;
}

/// Deletes every photo in one location, and everything that hangs off it.
///
/// Kept apart from [FirestoreService] because a photo is not only a document:
/// it owns a file in Storage and a subcollection of comments. Deleting the
/// document alone is what left orphaned files and comment threads in this
/// project before, so this removes all three.
class PhotoDeletionService {
  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  PhotoDeletionService({FirebaseFirestore? firestore, FirebaseStorage? storage})
    : _db = firestore ?? FirebaseFirestore.instance,
      _storage = storage ?? FirebaseStorage.instance;

  /// Firestore rejects a batch of more than 500 writes.
  static const _batchLimit = 500;

  /// Case- and whitespace-insensitive, matching how the feed groups photos
  /// into tabs. A tab labelled "Forbes Mill Museum" must delete the photos
  /// that tab shows, including any stored as "forbes mill museum ".
  static bool _same(String? a, String b) =>
      (a ?? '').trim().toLowerCase() == b.trim().toLowerCase();

  /// Whether one photo's stored fields put it inside the tab being deleted.
  ///
  /// Public and pure so the scoping rule can be tested directly: getting this
  /// wrong in either direction is destructive — too loose deletes another
  /// location's photos, too strict leaves behind photos the tab was showing.
  /// A photo must match BOTH the category and the location; a location name
  /// repeated under two categories is two different tabs.
  static bool matches(
    Map<String, dynamic> data, {
    required String category,
    required String locationName,
  }) {
    // An unnamed location is never a tab, so it can never be a delete target.
    if (locationName.trim().isEmpty) return false;
    // A field of the wrong type means the row is not shaped like a photo this
    // tab shows. Sparing it is the recoverable mistake; deleting it is not.
    final storedCategory = data['category'];
    final storedLocation = data['locationName'];
    if (storedCategory is! String || storedLocation is! String) return false;
    return _same(storedCategory, category) &&
        _same(storedLocation, locationName);
  }

  /// Finds the photos a given tab is showing.
  ///
  /// Reads the collection and filters in memory rather than querying on two
  /// fields, which is what every other read in this app does — the stored
  /// values vary in case and spacing, so an equality query would silently
  /// miss rows and delete less than the tab displays.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> photosIn({
    required String category,
    required String locationName,
  }) async {
    final snapshot = await _db.collection('photos').get();
    return snapshot.docs
        .where(
          (doc) => matches(
            doc.data(),
            category: category,
            locationName: locationName,
          ),
        )
        .toList();
  }

  /// Deletes one photo, its image file and its comments.
  ///
  /// The same cleanup the bulk delete does, for the single-photo menus. Pass
  /// [imageUrl] when the caller already has the photo loaded; without it the
  /// document is read first, because deleting the document is what makes the
  /// file unreachable — once it is gone there is nothing left pointing at the
  /// object in Storage.
  Future<BulkDeleteResult> deleteOne({
    required String photoId,
    String? imageUrl,
  }) async {
    final ref = _db.collection('photos').doc(photoId);

    var url = imageUrl;
    if (url == null || url.isEmpty) {
      try {
        url = (await ref.get()).data()?['imageUrl'] as String?;
      } catch (e, stack) {
        CrashReporting.recordError(
          e,
          stack,
          reason: '[delete] could not read $photoId',
        );
      }
    }

    var files = 0;
    var comments = 0;
    try {
      if (url != null && url.isNotEmpty) {
        if (await _deleteFile(url)) files++;
      }
      comments = await _deleteComments(photoId);
      await _deleteLikes(photoId);
    } catch (e, stack) {
      // Leaving the document in place keeps the photo visible and deletable
      // rather than stranding a file with nothing pointing at it.
      CrashReporting.recordError(
        e,
        stack,
        reason: '[delete] assets for $photoId',
      );
      return const BulkDeleteResult(failed: 1);
    }

    try {
      await ref.delete();
    } catch (e, stack) {
      CrashReporting.recordError(
        e,
        stack,
        reason: '[delete] document $photoId',
      );
      return BulkDeleteResult(
        filesDeleted: files,
        commentsDeleted: comments,
        failed: 1,
      );
    }

    return BulkDeleteResult(
      photosDeleted: 1,
      filesDeleted: files,
      commentsDeleted: comments,
    );
  }

  /// Deletes every photo in [locationName] within [category].
  ///
  /// Order matters: the file and the comments go first, so a failure partway
  /// leaves a photo that is still listed and still openable rather than a
  /// document-less file nobody can find or delete through the app.
  Future<BulkDeleteResult> deleteLocation({
    required String category,
    required String locationName,
  }) async {
    final docs = await photosIn(category: category, locationName: locationName);
    if (docs.isEmpty) return const BulkDeleteResult();

    var files = 0;
    var comments = 0;
    var failed = 0;
    final deletable = <DocumentReference>[];

    for (final doc in docs) {
      try {
        final url = doc.data()['imageUrl'] as String?;
        if (url != null && url.isNotEmpty) {
          if (await _deleteFile(url)) files++;
        }
        comments += await _deleteComments(doc.id);
        await _deleteLikes(doc.id);
        deletable.add(doc.reference);
      } catch (e, stack) {
        CrashReporting.recordError(
          e,
          stack,
          reason: '[delete] skipped ${doc.id}',
        );
        failed++;
      }
    }

    var deleted = 0;
    for (var i = 0; i < deletable.length; i += _batchLimit) {
      final slice = deletable.skip(i).take(_batchLimit).toList();
      final batch = _db.batch();
      for (final ref in slice) {
        batch.delete(ref);
      }
      try {
        await batch.commit();
        deleted += slice.length;
      } catch (e, stack) {
        CrashReporting.recordError(e, stack, reason: '[delete] batch failed');
        failed += slice.length;
      }
    }

    return BulkDeleteResult(
      photosDeleted: deleted,
      filesDeleted: files,
      commentsDeleted: comments,
      failed: failed,
    );
  }

  /// Resolves the Storage object from its download URL rather than rebuilding
  /// the path from category and id. The stored path is whatever the upload
  /// sanitised it to, and the URL is the only record of it that is guaranteed
  /// to be right.
  Future<bool> _deleteFile(String url) async {
    try {
      await _storage.refFromURL(url).delete();
      return true;
    } on FirebaseException catch (e) {
      // An already-missing object is the expected case for photos deleted by
      // the older document-only path, and is not a failure.
      if (e.code == 'object-not-found') return false;
      rethrow;
    }
  }

  Future<int> _deleteComments(String photoId) => _deleteAll(
    _db.collection('comments').doc(photoId).collection('messages'),
  );

  /// A photo's likes are a subcollection under it, and Firestore keeps a
  /// subcollection after its parent document is deleted.
  Future<int> _deleteLikes(String photoId) =>
      _deleteAll(_db.collection('photos').doc(photoId).collection('likes'));

  Future<int> _deleteAll(Query<Map<String, dynamic>> query) async {
    final snapshot = await query.get();
    if (snapshot.docs.isEmpty) return 0;

    var removed = 0;
    for (var i = 0; i < snapshot.docs.length; i += _batchLimit) {
      final slice = snapshot.docs.skip(i).take(_batchLimit).toList();
      final batch = _db.batch();
      for (final doc in slice) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      removed += slice.length;
    }
    return removed;
  }
}
