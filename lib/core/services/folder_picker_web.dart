import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

const _imageExtensions = {'.jpg', '.jpeg', '.png', '.webp', '.heic'};

/// Opens the browser's folder picker and reads back every image file inside,
/// recursively. One dialog, the whole tree — this is the thing the broken
/// "Select Folder" button was always meant to do.
Future<List<({String name, Uint8List bytes})>> pickFolderImages({
  int limit = 50,
}) async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..multiple = true;
  input.webkitdirectory = true;
  input.style.display = 'none';
  web.document.body?.append(input);

  try {
    final files = await awaitSelection(input);
    if (files == null) return [];

    final result = <({String name, Uint8List bytes})>[];
    for (var i = 0; i < files.length && result.length < limit; i++) {
      final file = files.item(i);
      if (file == null) continue;
      final lower = file.name.toLowerCase();
      if (!_imageExtensions.any(lower.endsWith)) continue;

      try {
        final buffer = await file.arrayBuffer().toDart;
        final bytes = buffer.toDart.asUint8List();
        if (bytes.isNotEmpty) result.add((name: file.name, bytes: bytes));
      } catch (_) {
        // One unreadable file (permissions, a mid-copy file) should not sink
        // the rest of the folder.
      }
    }
    return result;
  } finally {
    input.remove();
  }
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
