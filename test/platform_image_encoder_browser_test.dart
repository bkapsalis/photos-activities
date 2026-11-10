@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';

import 'support/encoder_check.dart';

/// Web. Skipped by a plain `flutter test`; run with --platform chrome.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  defineEncoderCheck();
}
