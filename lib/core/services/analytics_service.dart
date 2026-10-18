import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// The app's usage events, in one place.
///
/// Each Firebase project (dev, staging, prod) reports to its own Google
/// Analytics property, so testing never shows up in the real numbers.
///
/// Logging must never break the feature it describes: every call is
/// fire-and-forget and swallows its own errors. Nothing personal is sent —
/// ids, categories and place names only, never names, emails or text.
class AnalyticsService {
  AnalyticsService._();

  static FirebaseAnalytics? _analytics;
  static FirebaseAnalytics get _a => _analytics ??= FirebaseAnalytics.instance;

  static void _log(String what, Future<void> Function() call) {
    try {
      call().catchError((Object e) {
        debugPrint('[analytics] $what failed: $e');
      });
    } catch (e) {
      // FirebaseAnalytics.instance throws before Firebase is initialised,
      // which is the case in unit tests.
      debugPrint('[analytics] $what skipped: $e');
    }
  }

  // ── Screens ───────────────────────────────────────────
  // The app switches tabs in place and pushes unnamed routes, so a route
  // observer would see almost nothing; screens are reported explicitly.

  static void screen(String name) =>
      _log('screen $name', () => _a.logScreenView(screenName: name));

  // ── Accounts ──────────────────────────────────────────

  /// [method]: google, email or guest.
  static void login(String method) =>
      _log('login', () => _a.logLogin(loginMethod: method));

  /// A new account, or a guest registering one: email, google or apple.
  static void signUp(String method) =>
      _log('sign_up', () => _a.logSignUp(signUpMethod: method));

  // ── Content ───────────────────────────────────────────

  static void photoViewed(String photoId) => _log(
    'photo_view',
    () => _a.logEvent(name: 'photo_view', parameters: {'photo_id': photoId}),
  );

  static void photoUploaded({
    required String category,
    required bool hasLocation,
  }) => _log(
    'photo_upload',
    () => _a.logEvent(
      name: 'photo_upload',
      parameters: {
        'category': category,
        // Analytics parameters take strings and numbers, not booleans.
        'has_location': hasLocation ? 1 : 0,
      },
    ),
  );

  static void commentPosted(String photoId) => _log(
    'comment_post',
    () => _a.logEvent(name: 'comment_post', parameters: {'photo_id': photoId}),
  );

  static void directionsRequested(String locationName) => _log(
    'directions',
    () => _a.logEvent(
      name: 'directions_request',
      parameters: {'location': locationName},
    ),
  );

  // ── Browsing ──────────────────────────────────────────

  static void categorySelected(String category) => _log(
    'category',
    () => _a.logEvent(
      name: 'category_select',
      parameters: {'category': category},
    ),
  );

  /// [location] null is the "All" tab.
  static void locationSelected(String? location) => _log(
    'location',
    () => _a.logEvent(
      name: 'location_select',
      parameters: {'location': location ?? 'All'},
    ),
  );

  /// The in-app map of where one photo was taken was opened.
  static void photoMapOpened(String locationName) => _log(
    'photo_map',
    () => _a.logEvent(
      name: 'photo_map_open',
      parameters: {'location': locationName},
    ),
  );

  /// [mode]: masonry or carousel.
  static void viewModeChanged(String mode) => _log(
    'view_mode',
    () => _a.logEvent(name: 'view_mode_change', parameters: {'mode': mode}),
  );
}
