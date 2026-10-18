import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Gets the app permission to read where photos were taken, on Android.
///
/// Since Android 10 the system blanks the GPS tags out of every photo an app
/// reads from the gallery unless the app holds ACCESS_MEDIA_LOCATION. The
/// camera model, time and size still come through, so nothing looks wrong
/// until the photo has no place on the map. Measured on the emulator with a
/// photo carrying known GPS: picked without this permission, the tags arrive
/// zeroed.
///
/// Every other platform hands photos over unredacted, so this is a no-op
/// there.
class MediaLocationAccess {
  const MediaLocationAccess._();

  static const _channel = MethodChannel('bills_bay_area/media_location');

  /// True when photos picked from now on will keep their location. Never
  /// throws: a refusal or a missing handler just means uploads go ahead
  /// without a location, as before.
  static Future<bool> ensure() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      return await _channel.invokeMethod<bool>('requestMediaLocation') ?? false;
    } catch (e) {
      debugPrint('[metadata] could not request photo location access: $e');
      return false;
    }
  }

  /// The photo at Android content address [uri] read in full, GPS intact,
  /// or null when that is not possible — no permission, an older Android, or
  /// not a gallery item — and the caller should keep the bytes it has.
  ///
  /// Holding the permission is not enough on its own: Android only skips the
  /// redaction for an app that reopens the photo asking for the original.
  static Future<Uint8List?> readOriginal(String uri) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      return await _channel.invokeMethod<Uint8List>('readOriginal', {
        'uri': uri,
      });
    } catch (e) {
      debugPrint('[metadata] could not read original photo: $e');
      return null;
    }
  }
}
