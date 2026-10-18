import 'package:flutter/material.dart';

import '../../../core/models/models.dart';
import '../../../core/services/firestore_service.dart';

/// Where the reader was when they opened the map, so a second tap on the
/// map button puts them back there: the same screen, category, location
/// tab and search. The scroll position and carousel photo survive too,
/// because the feed is kept alive under the map; see [FeedUnderMap].
class MapReturnPoint<V> {
  /// The screen the map was opened from (a nav index, or the web's view).
  final V view;
  final int categoryIndex;
  final String? location;
  final String search;

  const MapReturnPoint({
    required this.view,
    required this.categoryIndex,
    required this.location,
    required this.search,
  });
}

/// The map shown over the feed rather than instead of it.
///
/// Swapping one for the other disposed the feed, so coming back from the
/// map always started at the top of the grid or the first carousel photo.
/// Kept offstage, the feed holds its place for the return trip.
class FeedUnderMap extends StatelessWidget {
  final bool showMap;

  /// False when the map was opened from somewhere other than this feed —
  /// Explore — so a hidden feed nobody is going back to isn't built.
  final bool keepFeed;
  final Widget map;
  final Widget feed;

  const FeedUnderMap({
    super.key,
    required this.showMap,
    required this.keepFeed,
    required this.map,
    required this.feed,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (keepFeed || !showMap)
          Offstage(
            offstage: showMap,
            child: TickerMode(enabled: !showMap, child: feed),
          ),
        if (showMap) map,
      ],
    );
  }
}

/// A category's photos from Firestore, subscribed once per category.
///
/// A StreamBuilder handed `streamPhotosByCategory(...)` straight from a
/// build method gets a new stream on every rebuild — a search keystroke, a
/// tab change, opening the map — and resubscribes each time, flashing the
/// spinner and throwing away the feed beneath it along with its scroll
/// position.
class CategoryPhotosBuilder extends StatefulWidget {
  final String category;
  final Widget Function(BuildContext context, List<PhotoPost> photos) builder;

  const CategoryPhotosBuilder({
    super.key,
    required this.category,
    required this.builder,
  });

  @override
  State<CategoryPhotosBuilder> createState() => _CategoryPhotosBuilderState();
}

class _CategoryPhotosBuilderState extends State<CategoryPhotosBuilder> {
  final _firestore = FirestoreService();
  late Stream<List<PhotoPost>> _photos = _firestore.streamPhotosByCategory(
    widget.category,
  );

  @override
  void didUpdateWidget(CategoryPhotosBuilder old) {
    super.didUpdateWidget(old);
    if (widget.category != old.category) {
      _photos = _firestore.streamPhotosByCategory(widget.category);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PhotoPost>>(
      stream: _photos,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        return widget.builder(context, snapshot.data ?? []);
      },
    );
  }
}
