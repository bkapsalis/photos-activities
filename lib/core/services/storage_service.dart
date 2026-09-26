import 'dart:io';

import 'package:flutter/foundation.dart';
import 'dart:ui' as ui;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import 'package:file_picker/file_picker.dart';

class PickedFileData {
  final String name;
  final Uint8List bytes;

  const PickedFileData({required this.name, required this.bytes});
}

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

  /// Decode the true width/height aspect ratio of an image from its raw bytes.
  /// Used so thumbnail grids can size each cell to the photo's real shape
  /// instead of cropping it to a fixed placeholder ratio.
  Future<double> getImageAspectRatio(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final ratio = frame.image.width / frame.image.height;
    frame.image.dispose();
    return ratio;
  }

  /// Pick an image from gallery or camera, unmodified.
  ///
  /// Deliberately passes no maxWidth, maxHeight or imageQuality. Any of those
  /// makes image_picker re-encode natively before Dart sees the bytes, which
  /// destroys the EXIF this app now reads for capture time, camera and GPS.
  /// Resizing happens afterwards in ImageProcessingService, once the metadata
  /// has been taken off the original.
  Future<XFile?> pickImage({ImageSource source = ImageSource.gallery}) async {
    final picker = ImagePicker();
    return await picker.pickImage(source: source);
  }

  /// Pick one image, by whichever route keeps the photo's location intact.
  ///
  /// Measured on all three platforms with a file carrying known GPS:
  ///
  /// | platform | route                     | GPS |
  /// |----------|---------------------------|-----|
  /// | iOS      | image_picker (PHPicker)   | kept |
  /// | web      | browser file input        | kept |
  /// | Android  | file_picker (documents)   | kept |
  /// | Android  | image_picker (gallery)    | **zeroed** |
  ///
  /// Android's system photo picker hands back the GPS tags with every value
  /// set to 0/0 — the position is gone before Dart sees the bytes, and no
  /// amount of parsing recovers it. The document picker reads the same file
  /// without that redaction, so Android gallery picks go through it instead.
  /// Camera capture is the app's own file and is not redacted, so it stays on
  /// image_picker everywhere.
  Future<PickedFileData?> pickSingleImage({
    ImageSource source = ImageSource.gallery,
  }) async {
    final useDocumentPicker =
        source == ImageSource.gallery &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android;

    if (useDocumentPicker) {
      final picked = await pickFilesViaFilePicker(limit: 1);
      return picked.isEmpty ? null : picked.first;
    }

    final image = await pickImage(source: source);
    if (image == null) return null;
    try {
      return PickedFileData(name: image.name, bytes: await image.readAsBytes());
    } catch (_) {
      if (kIsWeb) return null;
      final file = File(image.path);
      if (!await file.exists()) return null;
      return PickedFileData(name: image.name, bytes: await file.readAsBytes());
    }
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

  /// Pick files via FilePicker (allows Cmd+A / Ctrl+A to select all files in a folder)
  Future<List<PickedFileData>> pickFilesViaFilePicker({int limit = 50}) async {
    try {
      final result = await FilePicker.pickFiles(
        allowMultiple: true,
        type: FileType.image,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return [];

      final list = <PickedFileData>[];
      for (final file in result.files) {
        if (list.length >= limit) break;
        Uint8List? bytes = file.bytes;
        if (bytes == null && file.path != null) {
          final f = File(file.path!);
          if (await f.exists()) {
            bytes = await f.readAsBytes();
          }
        }
        if (bytes != null && bytes.isNotEmpty) {
          list.add(PickedFileData(name: file.name, bytes: bytes));
        }
      }
      return list;
    } catch (e) {
      print('Error in pickFilesViaFilePicker: $e');
      return [];
    }
  }

  /// Pick an entire directory folder and automatically load all image files inside it
  Future<List<PickedFileData>> pickFolderAndScanImages({int limit = 50}) async {
    try {
      final String? selectedDirectory = await FilePicker.getDirectoryPath();
      if (selectedDirectory == null || selectedDirectory.isEmpty) return [];

      final dir = Directory(selectedDirectory);
      if (!await dir.exists()) return [];

      final entities = await dir.list().toList();
      final validExts = {'.jpg', '.jpeg', '.png', '.webp', '.heic'};
      final list = <PickedFileData>[];

      for (final entity in entities) {
        if (list.length >= limit) break;
        if (entity is File) {
          final pathLower = entity.path.toLowerCase();
          final hasValidExt = validExts.any((ext) => pathLower.endsWith(ext));
          if (hasValidExt) {
            final bytes = await entity.readAsBytes();
            if (bytes.isNotEmpty) {
              final fileName = entity.path.split(Platform.pathSeparator).last;
              list.add(PickedFileData(name: fileName, bytes: bytes));
            }
          }
        }
      }
      return list;
    } catch (e) {
      print('Error in pickFolderAndScanImages: $e');
      return [];
    }
  }
}
