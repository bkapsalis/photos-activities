@TestOn('browser')
library;

import 'dart:math';

import 'package:bills_bay_area/core/utils/explore_picks.dart';
import 'package:flutter_test/flutter_test.dart';

/// Web. Skipped by a plain `flutter test`; run with --platform chrome.
void main() {
  test('Explore gets a shuffle seed in a browser, where bit shifts are '
      '32-bit', () {
    final random = Random(1);
    for (var i = 0; i < 1000; i++) {
      expect(newExploreSeed(random), greaterThanOrEqualTo(0));
    }
    expect(newExploreSeed(), greaterThanOrEqualTo(0));
  });
}
