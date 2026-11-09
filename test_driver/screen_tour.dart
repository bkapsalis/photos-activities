import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Saves the screen tour's pictures; see integration_test/screen_tour_test.dart.
Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final dir = Platform.environment['TOUR_DIR'] ?? 'build/screen_tour';
    final file = File('$dir/$name.png');
    await file.create(recursive: true);
    await file.writeAsBytes(bytes);
    return true;
  },
);
