import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show IconData, Icons;

/// Where the photos for an upload can come from: the two choices on the
/// "Upload Image or Images" screen. See photo_pickers.dart for what each
/// opens on each platform.
enum UploadSource {
  /// The phone's folders on Android, the Photos library on an iPhone, the
  /// computer's folders on the web.
  device,

  /// Google Drive on Android and the web; iCloud Drive, in Files, on an
  /// iPhone.
  cloud,
}

/// How [source] is labelled: one short line saying where it leads here.
({String title, String subtitle, IconData icon}) describeUploadSource(
  UploadSource source, {
  required bool isWeb,
  required TargetPlatform platform,
}) {
  // isWeb first: the web on an iPhone reports iOS, and is still a browser.
  final iPhone = !isWeb && platform == TargetPlatform.iOS;
  return switch (source) {
    UploadSource.device => (
      title: 'Photos on this device',
      subtitle: isWeb
          ? 'Folders on this computer'
          : iPhone
          ? 'Your Photos library'
          : 'Folders on this phone',
      icon: isWeb ? Icons.computer : Icons.smartphone,
    ),
    UploadSource.cloud => (
      title: 'Photos from the Cloud',
      subtitle: iPhone ? 'iCloud Drive' : 'Google Drive',
      icon: Icons.cloud_outlined,
    ),
  };
}

/// What to know before picking from [source], if anything: how to pick
/// several photos in a window the app cannot change.
///
/// - Android's, for Drive, ticks a photo only once one is already ticked: a
///   plain tap before that takes the one photo and closes. Press and hold
///   starts the ticking, in tiles and list alike.
/// - Google's, on a computer's browser, takes several photos only with a key
///   held down while clicking. A phone's browser has no such key.
String? uploadSourceNote(
  UploadSource source, {
  required bool isWeb,
  required TargetPlatform platform,
}) {
  if (source != UploadSource.cloud) return null;
  if (!isWeb) {
    return platform == TargetPlatform.android
        ? 'To pick several: press and hold the first photo until it is '
              'ticked, then tap the others, then tap Select.'
        : null;
  }
  if (platform == TargetPlatform.android || platform == TargetPlatform.iOS) {
    return null;
  }
  return 'Mac users: hold Command (⌘) and click photos to pick several.\n'
      'PC users: hold Ctrl and click photos to pick several.';
}

/// The line under "Upload Image or Images" in the upload menu.
const uploadSourcesSummary = 'From this device or the cloud';
