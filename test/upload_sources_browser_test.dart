@TestOn('browser')
library;

import 'package:bills_bay_area/core/utils/upload_sources.dart';
import 'package:bills_bay_area/features/home/widgets/upload_images_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Web. Skipped by a plain `flutter test`; run with --platform chrome.
void main() {
  // The platform is put back by each test itself: testWidgets checks it is,
  // before any tear-down runs.
  Future<void> pumpSources(WidgetTester tester, TargetPlatform platform) {
    debugDefaultTargetPlatformOverride = platform;
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UploadSourceList(
            sources: const [UploadSource.device, UploadSource.cloud],
            onPick: (_) {},
          ),
        ),
      ),
    );
  }

  testWidgets('a computer is told, under the cloud, how to pick several '
      'photos', (tester) async {
    await pumpSources(tester, TargetPlatform.macOS);

    final note = find.textContaining('hold Command (⌘)');
    expect(note, findsOneWidget);
    expect(find.textContaining('hold Ctrl'), findsOneWidget);
    expect(
      tester.getTopLeft(note).dy,
      greaterThan(tester.getBottomLeft(find.text('Google Drive')).dy),
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a phone is not', (tester) async {
    await pumpSources(tester, TargetPlatform.android);

    expect(find.textContaining('hold Command'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
