import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:web/web.dart' as web;

import 'google_drive_picker_web.dart' as drive;
import 'picked_image.dart';

const _photoExtensions = {'.jpg', '.jpeg', '.png', '.webp', '.heic'};

/// Loads Google's picker scripts while the upload screen is open, so that a
/// tap on "Photos from the Cloud" can open Google's sign-in window at once:
/// browsers block a window opened long after the tap that asked for it.
void preparePhotoPickers() => drive.prepare();

/// Whether "Photos from the Cloud" can be offered: only where this
/// environment has a key for Google's picker.
bool get cloudPhotosAvailable => drive.isConfigured;

/// A folder on the computer, from the browser's folder window: every photo
/// in it and its subfolders, newest first, unticked.
Future<List<PickedImage>> pickDevicePhotos({required int limit}) async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..multiple = true;
  input.webkitdirectory = true;
  input.style.display = 'none';
  web.document.body?.append(input);

  try {
    final files = await awaitSelection(input);
    if (files == null) return [];

    final photos = <web.File>[];
    for (var i = 0; i < files.length; i++) {
      final file = files.item(i);
      final name = file?.name.toLowerCase() ?? '';
      if (file != null && _photoExtensions.any(name.endsWith)) {
        photos.add(file);
      }
    }
    photos.sort((a, b) => b.lastModified.compareTo(a.lastModified));
    return [for (final file in photos.take(limit)) _filePhoto(file)];
  } finally {
    input.remove();
  }
}

/// Google Drive, in Google's own picker: the photos chosen there, ticked.
Future<List<PickedImage>> pickCloudPhotos({required int limit}) =>
    drive.pickPhotos(limit: limit);

/// A file on the computer: previewed by the browser straight from disk,
/// read into memory only if it is uploaded.
PickedImage _filePhoto(web.File file) {
  return PickedImage(
    name: file.name,
    preview: ResizeImage(
      NetworkImage(web.URL.createObjectURL(file)),
      width: PickedImage.previewWidth,
    ),
    read: () async => (await file.arrayBuffer().toDart).toDart.asUint8List(),
    selected: false,
  );
}

/// Resolves with the chosen [web.FileList], or `null` if the dialog was
/// cancelled.
///
/// Waits for the browser to say which: 'change' when files were chosen,
/// 'cancel' when they were not. Guessing a cancel from focus returning to
/// the page loses real selections: after a folder is picked Chrome asks
/// "Upload N files to this site?", and the page has focus again while that
/// question is still open. Both listeners are torn down the moment either
/// one settles the result.
@visibleForTesting
Future<web.FileList?> awaitSelection(web.HTMLInputElement input) {
  final completer = Completer<web.FileList?>();
  late final JSFunction changeListener;
  late final JSFunction cancelListener;

  void settle(web.FileList? files) {
    if (completer.isCompleted) return;
    input.removeEventListener('change', changeListener);
    input.removeEventListener('cancel', cancelListener);
    completer.complete(files);
  }

  changeListener = ((web.Event _) => settle(input.files)).toJS;
  cancelListener = ((web.Event _) => settle(null)).toJS;

  input.addEventListener('change', changeListener);
  input.addEventListener('cancel', cancelListener);
  input.click();

  return completer.future;
}
