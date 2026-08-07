import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/mock_data.dart';
import '../models/models.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Photo Operations ───────────────────────────────────

  CollectionReference get _photosRef => _db.collection('photos');

  /// Stream all photos for a category, ordered by newest first
  Stream<List<PhotoPost>> streamPhotosByCategory(String category) {
    final cat = category.trim().toLowerCase();
    return _photosRef
        .where('category', isEqualTo: cat)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs
          .map((doc) => PhotoPost.fromFirestore(doc))
          .toList();
      list.sort((a, b) => (b.createdAt ?? DateTime.now())
          .compareTo(a.createdAt ?? DateTime.now()));
      return list;
    });
  }

  /// Stream all photos (no filter)
  Stream<List<PhotoPost>> streamAllPhotos() {
    return _photosRef
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs
          .map((doc) => PhotoPost.fromFirestore(doc))
          .toList();
      list.sort((a, b) => (b.createdAt ?? DateTime.now())
          .compareTo(a.createdAt ?? DateTime.now()));
      return list;
    });
  }

  /// Seed initial sample data into Firestore if empty
  Future<void> seedSampleDataIfEmpty() async {
    try {
      final snapshot = await _photosRef.limit(1).get();
      if (snapshot.docs.isEmpty) {
        print('Seeding sample photos to Firestore...');
        for (final photo in MockPhotos.hikingPhotos) {
          final docRef = await _photosRef.add(photo.toFirestore());
          // Seed sample comments for this photo
          final commentsRef = _commentsRef(docRef.id);
          for (final comment in MockComments.photoComments) {
            await commentsRef.add(comment.toFirestore());
          }
        }

        // Seed sample chat messages for 'hiking' location chat
        final chatRef = _chatMessagesRef('hiking');
        for (final msg in MockChat.locationChat) {
          await chatRef.add(msg.toFirestore());
        }
        print('Sample data seeded successfully.');
      }
    } catch (e) {
      print('Error seeding sample data: $e');
    }
  }

  /// Get a single photo by ID
  Future<PhotoPost?> getPhoto(String photoId) async {
    try {
      final doc = await _photosRef.doc(photoId).get();
      if (!doc.exists) return null;
      return PhotoPost.fromFirestore(doc);
    } catch (e) {
      print('Error fetching photo: $e');
      return null;
    }
  }

  /// Add a new photo post
  Future<String?> addPhoto(PhotoPost photo) async {
    try {
      final docRef = await _photosRef.add(photo.toFirestore());
      return docRef.id;
    } catch (e) {
      print('Error adding photo: $e');
      return null;
    }
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
    final cat = category.trim().toLowerCase();
    await _photosRef.doc(photoId).update({
      'locationName': locationName,
      'locationRegion': region,
      'category': cat,
    });
  }

  /// Delete a photo
  Future<void> deletePhoto(String photoId) async {
    await _photosRef.doc(photoId).delete();
  }

  // ── Location Operations ────────────────────────────────

  CollectionReference get _locationsRef => _db.collection('locations');

  /// Stream locations by category
  Stream<List<Location>> streamLocationsByCategory(String category) {
    return _locationsRef
        .where('category', isEqualTo: category)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Location.fromFirestore(doc))
            .toList());
  }

  /// Get all locations
  Future<List<Location>> getLocations() async {
    try {
      final snapshot = await _locationsRef.get();
      return snapshot.docs.map((doc) => Location.fromFirestore(doc)).toList();
    } catch (e) {
      print('Error fetching locations: $e');
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
        .map((snapshot) => snapshot.docs
            .map((doc) => ChatMessage.fromFirestore(doc))
            .toList());
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
        .map((snapshot) => snapshot.docs
            .map((doc) => Comment.fromFirestore(doc))
            .toList());
  }

  /// Add a comment to a photo
  Future<void> addComment(String photoId, Comment comment) async {
    await _commentsRef(photoId).add(comment.toFirestore());
    // Also increment comment count on the photo
    await _photosRef.doc(photoId).update({
      'commentCount': FieldValue.increment(1),
    });
  }

  /// Update comment text
  Future<void> updateComment(String photoId, String commentId, String newText) async {
    await _commentsRef(photoId).doc(commentId).update({
      'text': newText,
    });
  }

  /// Delete a comment
  Future<void> deleteComment(String photoId, String commentId) async {
    await _commentsRef(photoId).doc(commentId).delete();
    await _photosRef.doc(photoId).update({
      'commentCount': FieldValue.increment(-1),
    });
  }
}
