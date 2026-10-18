import 'package:flutter/widgets.dart';

import '../../core/models/models.dart';

/// Which tab of the home feed to show — a category and one of its locations —
/// and which photo in it to bring into view.
@immutable
class FeedTarget {
  final int categoryIndex;
  final String locationName;

  /// The photo the reader was just looking at, so the carousel can open
  /// centred on it rather than on the tab's first photo.
  final String? photoId;

  const FeedTarget({
    required this.categoryIndex,
    required this.locationName,
    this.photoId,
  });
}

/// Sends the reader back to the home feed, opened on a particular location
/// tab, from pages several routes above it — such as a photo's map page.
///
/// The feed's category and tab live in HomeScreen at the bottom of the route
/// stack, so rather than threading a callback up through the photo page and
/// the map page, this posts the request to [requests], which HomeScreen
/// listens to, and closes every page above the feed.
class FeedNavigator {
  const FeedNavigator._();

  /// The latest request. HomeScreen listens; nothing else should.
  static final requests = ValueNotifier<FeedTarget?>(null);

  /// Closes every page above the feed and opens [photo]'s location tab,
  /// with [photo] centred if the carousel is showing.
  ///
  /// A photo whose category is not one of [categories] (none should be, but
  /// the stored value is free text) still returns to the feed, just without
  /// changing tabs.
  static void showLocationOf(
    BuildContext context,
    PhotoPost photo,
    List<String> categories,
  ) {
    final index = categoryIndexFor(
      photo.category.isNotEmpty ? photo.category : photo.location.category,
      categories,
    );
    if (index != null) {
      requests.value = FeedTarget(
        categoryIndex: index,
        locationName: photo.location.name.trim(),
        photoId: photo.id,
      );
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// [category]'s position in [categories], ignoring case and surrounding
  /// spaces the way the feed's own filtering does; null when absent.
  static int? categoryIndexFor(String category, List<String> categories) {
    final wanted = category.trim().toLowerCase();
    final index = categories.indexWhere(
      (c) => c.trim().toLowerCase() == wanted,
    );
    return index == -1 ? null : index;
  }
}
