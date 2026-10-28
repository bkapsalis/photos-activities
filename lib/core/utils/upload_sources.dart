import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show IconData, Icons;

/// Where the photos for an upload can come from.
///
/// Cloud drives are reached through the system's own file browser rather
/// than their APIs: Android's lists Google Drive, iPhone's Files lists
/// iCloud Drive and Google Drive, and a computer's file dialog shows
/// whatever drives are synced to it. None of that needs a sign-in to Google
/// or Apple from this app.
enum UploadSource {
  /// The phone's photo library. Android and iOS only: on the web the
  /// browser's file dialog is the photo library too, so it is [files].
  photoLibrary,

  /// The system file browser, cloud drives included.
  files,

  /// Every photo in one folder. Web only: neither Android nor iOS lets an
  /// app read a whole folder of photos.
  folder,
}

/// The sources offered on this platform, in the order shown.
List<UploadSource> uploadSourcesFor({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  if (isWeb) return const [UploadSource.files, UploadSource.folder];
  return switch (platform) {
    TargetPlatform.android ||
    TargetPlatform.iOS => const [UploadSource.photoLibrary, UploadSource.files],
    _ => const [UploadSource.files],
  };
}

/// How [source] is labelled on the "Upload Image or Images" screen. The
/// files source is named for the drives each platform's browser can reach.
({String title, String subtitle, IconData icon}) describeUploadSource(
  UploadSource source, {
  required bool isWeb,
  required TargetPlatform platform,
}) {
  return switch (source) {
    UploadSource.photoLibrary => (
      title: 'Photos on this device',
      subtitle: 'Pick one photo or several from your gallery.',
      icon: Icons.photo_library,
    ),
    UploadSource.files when isWeb => (
      title: 'Photos & files on this device',
      subtitle:
          'Google Drive and iCloud Drive appear here when they are on this '
          'computer. Select several with ⌘ or Ctrl, all with ⌘A or Ctrl+A.',
      icon: Icons.cloud_outlined,
    ),
    UploadSource.files when platform == TargetPlatform.iOS => (
      title: 'iCloud Drive & files',
      subtitle:
          'iCloud Drive, Google Drive and other places in Files. Tap Select '
          'to choose several.',
      icon: Icons.cloud_outlined,
    ),
    UploadSource.files => (
      title: 'Google Drive & files',
      subtitle:
          'Google Drive is at the top of the picker, or under ☰. '
          'Long-press to select several; ⋮ › Select all takes a whole folder.',
      icon: Icons.cloud_outlined,
    ),
    UploadSource.folder => (
      title: 'A whole folder',
      subtitle:
          'Shows every photo in a folder; then tap the ones to upload, '
          'or Select all.',
      icon: Icons.folder_open,
    ),
  };
}

/// One line under "Upload Image or Images" saying where photos can come
/// from here.
String uploadSourcesSummary({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  if (isWeb) return 'From your photos, files or a whole folder';
  return platform == TargetPlatform.iOS
      ? 'From your photos, iCloud Drive or Google Drive'
      : 'From your photos or Google Drive';
}
