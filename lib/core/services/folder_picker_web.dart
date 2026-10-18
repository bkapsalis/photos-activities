import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

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
    final files = await _awaitSelection(input);
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
/// There is no cancel event for `<input type=file>`: the only signal is
/// focus returning to the page without a 'change' having fired first. Both
/// listeners are torn down the moment either one settles the result, so a
/// cancel never leaves a stray listener behind to fire on some later,
/// unrelated focus change.
Future<web.FileList?> _awaitSelection(web.HTMLInputElement input) {
  final completer = Completer<web.FileList?>();
  late final JSFunction changeListener;
  late final JSFunction focusListener;

  void cleanup() {
    input.removeEventListener('change', changeListener);
    web.window.removeEventListener('focus', focusListener);
  }

  changeListener = ((web.Event _) {
    if (completer.isCompleted) return;
    cleanup();
    completer.complete(input.files);
  }).toJS;

  focusListener = ((web.Event _) {
    // The OS dialog just closed. In every major browser 'change' fires
    // before focus returns to the page when a selection was made, so if
    // nothing has arrived shortly after, this was a cancel.
    Future.delayed(const Duration(milliseconds: 300), () {
      if (completer.isCompleted) return;
      cleanup();
      completer.complete(null);
    });
  }).toJS;

  input.addEventListener('change', changeListener);
  web.window.addEventListener('focus', focusListener);
  input.click();

  return completer.future;
}
