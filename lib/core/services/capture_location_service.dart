import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Where the phone is, for photos taken inside the app.
///
/// A photo taken with the Pixel Camera app carries its GPS, but the same
/// camera leaves the location out when another app asks it to take the
/// photo — as "Take a Photo" does. Measured on a Pixel 7 Pro: gallery
/// uploads mapped, every in-app capture arrived with no GPS tags at all.
/// So for an in-app capture the app records where the phone is instead.
///
/// Android and iOS only. On the web a "camera" button may just open a file
/// chooser, and a laptop's position says nothing about where a chosen file
/// was taken.
///
/// Never throws: location switched off, permission refused or no fix in
/// time all mean the photo is uploaded without a location, as before.
class CaptureLocationService {
  const CaptureLocationService._();

  /// How long to wait for a fresh fix before settling for the last known one.
  static const _fixTimeout = Duration(seconds: 15);

  static bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Asks for location access, if it has not been decided yet. Call before
  /// opening the camera, so the prompt does not compete with it. True when a
  /// position can be read.
  static Future<bool> prepare() async {
    if (!_supported) return false;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        debugPrint('[location] device location is switched off');
        return false;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      final granted =
          permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
      if (!granted) debugPrint('[location] permission $permission');
      return granted;
    } catch (e) {
      debugPrint('[location] could not check permission: $e');
      return false;
    }
  }

  /// The phone's position now, or null. Falls back to the last known
  /// position when no fresh fix arrives in time — indoors, say.
  static Future<({double latitude, double longitude})?> current() async {
    if (!_supported) return null;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: _fixTimeout,
        ),
      );
      return (latitude: position.latitude, longitude: position.longitude);
    } catch (e) {
      debugPrint('[location] no fresh fix ($e); trying last known');
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last == null) return null;
        return (latitude: last.latitude, longitude: last.longitude);
      } catch (_) {
        return null;
      }
    }
  }
}
