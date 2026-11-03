import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How a category or location tab lays out its photos.
enum PhotoViewMode {
  /// The staggered grid, each tile as tall as its photo's shape needs.
  masonry,

  /// A thumbnail strip with the selected photo shown large beneath it.
  carousel;

  PhotoViewMode get toggled =>
      this == PhotoViewMode.masonry ? PhotoViewMode.carousel : PhotoViewMode.masonry;
}

/// Remembers the reader's chosen [PhotoViewMode] across app restarts.
///
/// A preference, not data: it lives on the device (localStorage on web) and
/// never in Firestore. Failing to read or write it must never get in the way
/// of showing photos, so both directions swallow their own errors and fall
/// back to the grid.
class ViewModeService {
  static const prefsKey = 'photo_view_mode';

  Future<PhotoViewMode> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return PhotoViewMode.values.asNameMap()[prefs.getString(prefsKey)] ??
          PhotoViewMode.masonry;
    } catch (e) {
      debugPrint('[view mode] could not read preference: $e');
      return PhotoViewMode.masonry;
    }
  }

  Future<void> save(PhotoViewMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, mode.name);
    } catch (e) {
      debugPrint('[view mode] could not save preference: $e');
    }
  }
}
