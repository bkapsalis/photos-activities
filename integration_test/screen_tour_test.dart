import 'dart:io' show Platform;

import 'package:bills_bay_area/core/widgets/orientation_policy.dart';
import 'package:bills_bay_area/features/auth/account_button.dart';
import 'package:bills_bay_area/features/home/widgets/photo_card.dart';
import 'package:bills_bay_area/main_dev.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Pictures of the main screens on whatever device it runs on: upright, and
/// on a tablet sideways too. Against the dev project, as a guest if no one
/// is signed in. For checking layouts where nothing can be tapped by hand
/// (the iOS Simulator), and for store screenshots.
///
///   flutter drive --flavor dev -t integration_test/screen_tour_test.dart \
///     --driver test_driver/screen_tour.dart -d DEVICE_ID
///
/// The pictures land in build/screen_tour/, or in $TOUR_DIR.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('screen tour', (tester) async {
    // Real time passes: photos load from the network.
    Future<void> wait(int seconds) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> shot(String name) async {
      await wait(2);
      await binding.takeScreenshot(name);
    }

    Future<void> back() async {
      await tester.binding.handlePopRoute();
      await wait(2);
    }

    // Tooltip on the wide layout, label on the phone's bottom bar.
    Finder button(String name) {
      final tooltip = find.byTooltip(name);
      return tooltip.evaluate().isNotEmpty ? tooltip : find.text(name);
    }

    // The app installs crash reporting over the test's error handlers.
    final flutterOnError = FlutterError.onError;
    app.main();
    await wait(8);

    final guest = find.text('Continue as Guest');
    if (guest.evaluate().isNotEmpty) {
      await shot('0-sign-in');
      await tester.tap(guest);
      await wait(8);
    }
    if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();

    final view = tester.view;
    final phone = isPhoneSized(view.physicalSize / view.devicePixelRatio);

    for (final way in phone ? ['upright'] : ['upright', 'sideways']) {
      if (way == 'sideways') {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
        ]);
        await wait(4);
      }
      await shot('$way-1-home');

      await tester.tap(find.byType(PhotoCard).first);
      await wait(5);
      await shot('$way-2-photo');
      await back();

      // The sidebar's list, or the sheet the top bar opens without one.
      final chats = find.byTooltip('Location Chats');
      if (chats.evaluate().isNotEmpty) {
        await tester.tap(chats.first);
        await wait(3);
        await shot('$way-3-chat-list');
      }
      await tester.tap(find.byIcon(Icons.chat_bubble_outline).last);
      await wait(4);
      await shot('$way-4-chat');
      await back();

      await tester.tap(button('Explore').first);
      await wait(4);
      await shot('$way-5-explore');
      await tester.tap(button(phone ? 'Explore' : 'Back to all photos').first);
      await wait(2);

      await tester.tap(button('Map').first);
      await wait(6);
      await shot('$way-6-map');
      await tester.tap(button(phone ? 'Map' : 'Back to all photos').first);
      await wait(2);

      await tester.tap(find.byType(AccountButton).first);
      await wait(2);
      await tester.tap(find.text('Profile').last);
      await wait(4);
      await shot('$way-7-profile');
      await back();
    }

    await SystemChrome.setPreferredOrientations([]);
    FlutterError.onError = flutterOnError;
  });
}
