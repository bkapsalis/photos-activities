import 'dart:io';

import 'package:flutter/foundation.dart';
import 'dart:ui' as ui;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import 'package:file_picker/file_picker.dart';

import 'crash_reporting.dart';
import 'media_location_access.dart';

class PickedFileData {
  final String name;
  final Uint8List bytes;

  const PickedFileData({required this.name, required this.bytes});
}

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Tags the file with its uploader. storage.rules require this tag to
  /// match the caller on upload, and check it before letting anyone but a
  /// moderator delete the file — nothing else ties a file to a person.
  SettableMetadata _uploadMetadata() => SettableMetadata(
    contentType: 'image/jpeg',
    customMetadata: {
      if (FirebaseAuth.instance.currentUser case final user?)
        'ownerUid': user.uid,
    },
  );

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

      final uploadTask = await ref.putFile(file, _uploadMetadata());

      if (uploadTask.state == TaskState.success) {
        return await ref.getDownloadURL();
      }
      return null;
    } catch (e, stack) {
      CrashReporting.recordError(e, stack, reason: 'uploading photo');
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
      final sanitizedCategory = category.trim().toLowerCase().replaceAll(
        RegExp(r'\s+'),
        '-',
      );
      final storagePath = 'photos/$sanitizedCategory/$photoId.jpg';
      final ref = _storage.ref().child(storagePath);

      final uploadTask = await ref.putData(bytes, _uploadMetadata());

      if (uploadTask.state == TaskState.success) {
        return await ref.getDownloadURL();
      }
      return null;
    } catch (e, stack) {
      CrashReporting.recordError(e, stack, reason: 'uploading bytes');
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
      return await uploadBytes(
        bytes: bytes,
        category: category,
        photoId: photoId,
      );
    } catch (e, stack) {
      CrashReporting.recordError(e, stack, reason: 'uploading XFile');
      return null;
    }
  }

  /// Removes a file this app has just uploaded, by its download URL, when
  /// the photo it belongs to could not be saved: with no document pointing
  /// at it, nothing would ever show or delete it. Best effort: a failure is
  /// reported, never thrown, so it cannot hide the error that led here.
  Future<void> deleteUploadedFile(String downloadUrl) async {
    try {
      await _storage.refFromURL(downloadUrl).delete();
    } catch (error, stack) {
      CrashReporting.recordError(
        error,
        stack,
        reason: 'could not remove an upload whose photo was not saved',
      );
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
    } catch (e, stack) {
      CrashReporting.recordError(e, stack, reason: 'deleting photo');
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
    } catch (e, stack) {
      CrashReporting.recordError(e, stack, reason: 'getting photo URL');
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
  /// Measured with a file carrying known GPS:
  ///
  /// | platform | route                                        | GPS |
  /// |----------|----------------------------------------------|-----|
  /// | iOS      | image_picker (PHPicker)                      | kept |
  /// | web      | browser file input                           | kept |
  /// | Android  | file_picker (documents), reread as original  | kept |
  /// | Android  | file_picker (documents), as handed over      | **zeroed** |
  /// | Android  | image_picker (gallery)                       | **zeroed** |
  ///
  /// Android hands back the GPS tags with every value set to 0/0 unless the
  /// app holds ACCESS_MEDIA_LOCATION *and* reopens the photo asking for the
  /// original — the position is gone before Dart sees the bytes otherwise,
  /// and no amount of parsing recovers it. (The document picker once avoided
  /// this; measured again 2026-10-17 on the Android 16 emulator, it no longer
  /// does.) So Android gallery picks go through the document picker, whose
  /// results carry the content address needed to reread the original; see
  /// [pickFilesViaFilePicker] and MediaLocationAccess. Camera capture is the
  /// app's own file and is not redacted, so it stays on image_picker
  /// everywhere — though the Pixel Camera leaves the location out of photos
  /// taken for another app, so the upload dialog adds the phone's position
  /// instead (CaptureLocationService).
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

  /// Pick files via FilePicker (allows Cmd+A / Ctrl+A to select all files in a folder)
  Future<List<PickedFileData>> pickFilesViaFilePicker({int limit = 50}) async {
    try {
      // Android hands over photos with their GPS blanked unless the app has
      // asked for photo locations; see MediaLocationAccess.
      final canReadLocation = await MediaLocationAccess.ensure();
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
        // Reread from the gallery as the original, so the GPS survives. The
        // picker's own copy has it zeroed on Android.
        final identifier = file.identifier;
        if (canReadLocation && identifier != null) {
          final original = await MediaLocationAccess.readOriginal(identifier);
          if (original != null && original.isNotEmpty) bytes = original;
        }
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
    } catch (e, stack) {
      CrashReporting.recordError(e, stack, reason: 'picking files');
      return [];
    }
  }
}
