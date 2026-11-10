import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';

/// Hands a destination to whichever map app the device prefers.
///
/// Each platform has a different idea of "the preferred map", so this asks
/// the platform in its own language rather than forcing Google Maps on
/// everyone:
///
/// * **Android** — a `geo:` URI is the system's "here is a place" intent.
///   Android shows the user's default map app, or a chooser if they have
///   several. Someone who prefers Waze or OsmAnd gets Waze or OsmAnd.
/// * **iOS** — `maps://` opens Apple Maps, the system default. iOS has no
///   equivalent of Android's chooser, so there is no way to honour a
///   third-party preference without asking the user directly.
/// * **Web and anything else** — the universal Google Maps directions URL,
///   which opens the installed app on mobile browsers and the site otherwise.
///
/// Every platform falls back to that universal URL if the native scheme
/// cannot be opened, so a device with no map app still reaches directions in
/// a browser.
class Directions {
  const Directions._();

  /// Returns null on success, or a message explaining why it did not open.
  static Future<String?> toLocation(Location location) async {
    if (!location.hasCoordinates) {
      return 'This photo has no precise location to navigate to.';
    }

    final lat = location.latitude!;
    final lng = location.longitude!;
    final label = Uri.encodeComponent(location.name);

    final universal = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
    );

    final preferred = switch (defaultTargetPlatform) {
      TargetPlatform.android => Uri.parse('geo:$lat,$lng?q=$lat,$lng($label)'),
      TargetPlatform.iOS => Uri.parse('maps://?daddr=$lat,$lng&dirflg=d'),
      _ => universal,
    };

    // kIsWeb short-circuits: a browser cannot open a native scheme, and
    // canLaunchUrl is unreliable there.
    final candidates = kIsWeb ? [universal] : [preferred, universal];

    for (final uri in candidates) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return null;
        }
      } catch (_) {
        // Try the next candidate rather than failing outright.
      }
    }
    return 'Could not open a map app for directions.';
  }
}
