import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'keep_picking.dart';
import 'media_location_access.dart';
import 'picked_image.dart';

/// Android's PhotoPicker.kt and iOS's PhotoPicker.swift.
const _channel = MethodChannel('bills_bay_area/photo_picker');

/// Nothing to get ready ahead of a pick here; see the web version.
void preparePhotoPickers() {}

/// Phones always have a cloud to pick from: Drive on Android, Files on iOS.
bool get cloudPhotosAvailable => true;

/// Android: a folder on the phone, every photo in it unticked. iPhone: the
/// Photos library, the photos chosen there ticked.
Future<List<PickedImage>> pickDevicePhotos({required int limit}) {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return _pickFromPhotosLibrary(limit);
  }
  return _pickNative('pickDeviceFolder', limit: limit, selected: false);
}

/// Android: Google Drive, the photos chosen there ticked, the picker opening
/// again after each photo picked alone (see [keepPicking]). iPhone: a folder
/// in Files, every photo in it unticked.
Future<List<PickedImage>> pickCloudPhotos({required int limit}) async {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return _pickNative('pickCloudFolder', limit: limit, selected: false);
  }
  final found = await keepPicking<Map<Object?, Object?>>(
    limit: limit,
    idOf: (photo) => photo['id']!,
    pick: ({required chosen, required room, required after}) => _findNative(
      'pickCloudPhotos',
      limit: room,
      // Back goes up a folder at a time before it closes the picker.
      note: after == null
          ? null
          : keepPickingNote(chosen, toFinish: 'press Back until this closes'),
    ),
  );
  return [for (final photo in found) _fromNative(photo, selected: true)];
}

/// The photo library's picker hands over the originals, GPS included.
Future<List<PickedImage>> _pickFromPhotosLibrary(int limit) async {
  // image_picker refuses a limit below 2.
  final photos = await ImagePicker().pickMultiImage(
    limit: limit < 2 ? 2 : limit,
  );
  return [
    for (final photo in photos.take(limit))
      PickedImage(
        name: photo.name,
        preview: ResizeImage(
          FileImage(File(photo.path)),
          width: PickedImage.previewWidth,
        ),
        read: photo.readAsBytes,
      ),
  ];
}

Future<List<PickedImage>> _pickNative(
  String method, {
  required int limit,
  required bool selected,
}) async {
  final found = await _findNative(method, limit: limit);
  return [for (final photo in found) _fromNative(photo, selected: selected)];
}

/// Opens the native picker [method] names, with [note] shown over it if
/// given. Answers empty when nothing was picked, and throws when what was
/// picked could not be read.
Future<List<Map<Object?, Object?>>> _findNative(
  String method, {
  required int limit,
  String? note,
}) async {
  // Without this Android blanks the GPS out of every photo it hands over.
  await MediaLocationAccess.ensure();
  final found = await _channel.invokeListMethod<Map<Object?, Object?>>(method, {
    'limit': limit,
    'note': ?note,
  });
  return found ?? const [];
}

PickedImage _fromNative(Map<Object?, Object?> photo, {required bool selected}) {
  return nativePhoto(
    id: photo['id']! as String,
    name: photo['name']! as String,
    selected: selected,
  );
}

/// A photo the native side named by [id], previewed and read through it.
@visibleForTesting
PickedImage nativePhoto({
  required String id,
  required String name,
  required bool selected,
}) {
  return PickedImage(
    name: name,
    preview: LazyBytesImage(
      id,
      () => _channel.invokeMethod<Uint8List>('thumbnail', {
        'id': id,
        'size': PickedImage.previewWidth,
      }),
    ),
    read: () async {
      final bytes = await _channel.invokeMethod<Uint8List>('read', {'id': id});
      if (bytes == null || bytes.isEmpty) {
        throw StateError('$name could not be read');
      }
      return bytes;
    },
    selected: selected,
  );
}
