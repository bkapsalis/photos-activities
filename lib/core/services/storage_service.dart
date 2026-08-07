import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Upload a photo to Firebase Storage
  /// Returns the download URL on success, null on failure
  Future<String?> uploadPhoto({
    required String filePath,
    required String category,
    required String photoId,
  }) async {
    try {
      final file = File(filePath);
      final storagePath = 'photos/${category.toLowerCase()}/$photoId.jpg';
      final ref = _storage.ref().child(storagePath);

      final uploadTask = await ref.putFile(
        file,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      if (uploadTask.state == TaskState.success) {
        return await ref.getDownloadURL();
      }
      return null;
    } catch (e) {
      print('Error uploading photo: $e');
      return null;
    }
  }

  /// Upload raw image bytes to Firebase Storage
  Future<String?> uploadBytes({
    required Uint8List bytes,
    required String category,
    required String photoId,
  }) async {
    try {
      final sanitizedCategory = category.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-');
      final storagePath = 'photos/$sanitizedCategory/$photoId.jpg';
      final ref = _storage.ref().child(storagePath);

      final uploadTask = await ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      if (uploadTask.state == TaskState.success) {
        return await ref.getDownloadURL();
      }
      return null;
    } catch (e) {
      print('Error uploading bytes: $e');
      return null;
    }
  }

  /// Upload from XFile (from image_picker, supports Mobile & Web)
  Future<String?> uploadXFile({
    required XFile xFile,
    required String category,
    required String photoId,
  }) async {
    try {
      final bytes = await xFile.readAsBytes();
      return uploadBytes(bytes: bytes, category: category, photoId: photoId);
    } catch (e) {
      print('Error uploading XFile: $e');
      return null;
    }
  }

  /// Delete a photo from Storage
  Future<void> deletePhoto({
    required String category,
    required String photoId,
  }) async {
    try {
      final storagePath = 'photos/${category.toLowerCase()}/$photoId.jpg';
      await _storage.ref().child(storagePath).delete();
    } catch (e) {
      print('Error deleting photo: $e');
    }
  }

  /// Get download URL for an existing photo
  Future<String?> getPhotoUrl({
    required String category,
    required String photoId,
  }) async {
    try {
      final storagePath = 'photos/${category.toLowerCase()}/$photoId.jpg';
      return await _storage.ref().child(storagePath).getDownloadURL();
    } catch (e) {
      print('Error getting photo URL: $e');
      return null;
    }
  }

  /// Pick an image from gallery or camera
  Future<XFile?> pickImage({
    ImageSource source = ImageSource.gallery,
    int maxWidth = 1920,
    int maxHeight = 1920,
    int quality = 85,
  }) async {
    final picker = ImagePicker();
    return await picker.pickImage(
      source: source,
      maxWidth: maxWidth.toDouble(),
      maxHeight: maxHeight.toDouble(),
      imageQuality: quality,
    );
  }

  /// Pick multiple images from gallery (up to [limit])
  Future<List<XFile>> pickMultiImage({
    int limit = 50,
  }) async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage(
      limit: limit,
    );
    // Enforce limit client-side as a safety net
    if (images.length > limit) {
      return images.sublist(0, limit);
    }
    return images;
  }
}
