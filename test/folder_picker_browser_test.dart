@TestOn('browser')
library;

import 'package:bills_bay_area/core/services/folder_picker_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

/// Web. Skipped by a plain `flutter test`; run with --platform chrome.
void main() {
  web.HTMLInputElement folderInput() => web.HTMLInputElement()..type = 'file';

  test('a folder confirmed after the page regains focus is still '
      'picked', () async {
    // Chrome's "Upload N files to this site?" question is answered after
    // the folder dialog has closed and the page has focus back.
    final input = folderInput();
    final picked = awaitSelection(input);
    web.window.dispatchEvent(web.Event('focus'));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    input.dispatchEvent(web.Event('change'));

    expect(await picked, isNotNull);
  });

  test('closing the dialog without choosing reports nothing picked', () async {
    final input = folderInput();
    final picked = awaitSelection(input);
    input.dispatchEvent(web.Event('cancel'));

    expect(await picked, isNull);
  });
}
