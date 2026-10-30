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

/// The line under "Upload Image or Images" in the upload menu.
const uploadSourcesSummary = 'From this device or the cloud';
