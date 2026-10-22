import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/models.dart';
import 'analytics_service.dart';
import 'crash_reporting.dart';
import 'performance_service.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Reads each document on its own, skipping (and reporting) any that
  /// cannot be read, rather than failing the whole list. One malformed
  /// comment must not hide every other comment on the photo.
  static List<T> _parseEach<T>(
    Iterable<DocumentSnapshot> docs,
    T Function(DocumentSnapshot doc) parse,
  ) {
    final items = <T>[];
    for (final doc in docs) {
      try {
        items.add(parse(doc));
      } catch (error, stack) {
        CrashReporting.recordError(
          error,
          stack,
          reason: 'unreadable document ${doc.reference.path}',
        );
      }
    }
    return items;
  }

  // ── Photo Operations ───────────────────────────────────

  CollectionReference get _photosRef => _db.collection('photos');

  /// Stream all photos for a category (case-insensitive), ordered by newest first
  Stream<List<PhotoPost>> streamPhotosByCategory(String category) {
    final target = category.trim().toLowerCase();
    return _photosRef.snapshots().map((snapshot) {
      final list = _parseEach(snapshot.docs, PhotoPost.fromFirestore)
          .where((photo) => photo.category.trim().toLowerCase() == target)
          .toList();
      list.sort(
        (a, b) => (b.createdAt ?? DateTime.now()).compareTo(
          a.createdAt ?? DateTime.now(),
        ),
      );
      return list;
    });
  }

  /// Stream all photos (no filter)
  Stream<List<PhotoPost>> streamAllPhotos() {
    return _photosRef.snapshots().map((snapshot) {
      final list = _parseEach(snapshot.docs, PhotoPost.fromFirestore);
      list.sort(
        (a, b) => (b.createdAt ?? DateTime.now()).compareTo(
          a.createdAt ?? DateTime.now(),
        ),
      );
      return list;
    });
  }

  /// Stream photos filtered by category AND location name (case-insensitive)
  Stream<List<PhotoPost>> streamPhotosByLocation(
    String category,
    String locationName,
  ) {
    final targetCat = category.trim().toLowerCase();
    final targetLoc = locationName.trim().toLowerCase();
    return _photosRef.snapshots().map((snapshot) {
      final list = _parseEach(snapshot.docs, PhotoPost.fromFirestore)
          .where(
            (photo) =>
                photo.category.trim().toLowerCase() == targetCat &&
                photo.location.name.trim().toLowerCase() == targetLoc,
          )
          .toList();
      list.sort(
        (a, b) => (b.createdAt ?? DateTime.now()).compareTo(
          a.createdAt ?? DateTime.now(),
        ),
      );
      return list;
    });
  }

  /// Stream distinct location names for a category (derived from photos)
  Stream<List<String>> streamDistinctLocations(String category) {
    final target = category.trim().toLowerCase();
    return _photosRef.snapshots().map((snapshot) {
      final locations = <String>{};
      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        final cat = (data['category'] as String? ?? '').trim().toLowerCase();
        if (cat == target) {
          final name = (data['locationName'] as String? ?? '').trim();
          if (name.isNotEmpty) locations.add(name);
        }
      }
      final sorted = locations.toList()..sort();
      return sorted;
    });
  }

  /// Get a single photo by ID
  Future<PhotoPost?> getPhoto(String photoId) async {
    try {
      final doc = await _photosRef.doc(photoId).get();
      if (!doc.exists) return null;
      return PhotoPost.fromFirestore(doc);
    } catch (e, stack) {
      CrashReporting.recordError(e, stack, reason: 'fetching photo');
      return null;
    }
  }

  /// Adds a photo post and returns its id. Throws if it could not be saved,
  /// so a caller cannot mistake a failure for a success.
  Future<String> addPhoto(PhotoPost photo) async {
    final docRef = await PerformanceService.trace(
      'firestore_add_photo',
      () => _photosRef.add(photo.toFirestore()),
    );
    AnalyticsService.photoUploaded(
      category: photo.category,
      hasLocation: photo.location.hasCoordinates,
    );
    return docRef.id;
  }

  /// Update heart count
  Future<void> incrementHeartCount(String photoId) async {
    await _photosRef.doc(photoId).update({
      'heartCount': FieldValue.increment(1),
    });
  }

  /// Update photo details (location name, region, category)
  Future<void> updatePhotoDetails(
    String photoId, {
    required String locationName,
    String? region,
    required String category,
  }) async {
    await _photosRef.doc(photoId).update({
      'locationName': locationName,
      'locationRegion': region,
      'category': category.trim(),
    });
  }

  // Photo deletion deliberately lives in PhotoDeletionService, not here.
  // A photo owns an image file in Storage and a subcollection of comments,
  // and removing only this document leaves both stranded with nothing
  // pointing at them — which is exactly what the old deletePhoto did.

  // ── Location Operations ────────────────────────────────

  CollectionReference get _locationsRef => _db.collection('locations');

  /// Stream locations by category
  Stream<List<Location>> streamLocationsByCategory(String category) {
    return _locationsRef
        .where('category', isEqualTo: category)
        .snapshots()
        .map((snapshot) => _parseEach(snapshot.docs, Location.fromFirestore));
  }

  /// Get all locations
  Future<List<Location>> getLocations() async {
    try {
      final snapshot = await _locationsRef.get();
      return _parseEach(snapshot.docs, Location.fromFirestore);
    } catch (e, stack) {
      CrashReporting.recordError(e, stack, reason: 'fetching locations');
      return [];
    }
  }

  // ── Chat Operations (Location Chat) ────────────────────

  CollectionReference _chatMessagesRef(String locationId) =>
      _db.collection('chats').doc(locationId).collection('messages');

  /// Stream chat messages for a location
  Stream<List<ChatMessage>> streamChatMessages(String locationId) {
    return _chatMessagesRef(locationId)
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map(
          (snapshot) => _parseEach(snapshot.docs, ChatMessage.fromFirestore),
        );
  }

  /// Send a chat message
  Future<void> sendChatMessage(String locationId, ChatMessage message) async {
    await _chatMessagesRef(locationId).add(message.toFirestore());
  }

  // ── Comment Operations (Picture Chat) ──────────────────

  CollectionReference _commentsRef(String photoId) =>
      _db.collection('comments').doc(photoId).collection('messages');

  /// Stream comments for a photo
  Stream<List<Comment>> streamComments(String photoId) {
    return _commentsRef(photoId)
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snapshot) => _parseEach(snapshot.docs, Comment.fromFirestore));
  }

  /// Adds a comment to a photo and counts it, as one write: either both
  /// happen or neither does, so the count shown on the photo cannot drift.
  Future<void> addComment(String photoId, Comment comment) async {
    final batch = _db.batch()
      ..set(_commentsRef(photoId).doc(), comment.toFirestore())
      ..update(_photosRef.doc(photoId), {
        'commentCount': FieldValue.increment(1),
      });
    await batch.commit();
    AnalyticsService.commentPosted(photoId);
  }

  /// Update comment text
  Future<void> updateComment(
    String photoId,
    String commentId,
    String newText,
  ) async {
    await _commentsRef(photoId).doc(commentId).update({'text': newText});
  }

  /// Deletes a comment and uncounts it, as one write.
  Future<void> deleteComment(String photoId, String commentId) async {
    final batch = _db.batch()
      ..delete(_commentsRef(photoId).doc(commentId))
      ..update(_photosRef.doc(photoId), {
        'commentCount': FieldValue.increment(-1),
      });
    await batch.commit();
  }
}
