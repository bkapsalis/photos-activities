import '../models/models.dart';
import 'photo_sorting.dart';

/// Builds the Explore feed: the best-liked photos from every location, most
/// likes first.
///
/// "Sub category" here means a location name — the same grouping the location
/// tab strip uses — so every location gets represented no matter how few
/// photos it has. Taking the top [perLocation] from each group before
/// ranking is what keeps a single very active location from filling the
/// screen: a location with 200 photos contributes exactly as many as one
/// with 3.
extension ExplorePicks on List<PhotoPost> {
  List<PhotoPost> topLikedPerLocation({int perLocation = 2}) {
    if (isEmpty) return const [];

    final byLocation = <String, List<PhotoPost>>{};
    for (final photo in this) {
      final name = photo.location.name.trim();
      if (name.isEmpty) continue;
      byLocation.putIfAbsent(name, () => <PhotoPost>[]).add(photo);
    }

    final picks = <PhotoPost>[];
    for (final group in byLocation.values) {
      picks.addAll(group.sortedByPopularity().take(perLocation));
    }

    // Rank the picks themselves too, the way the location tabs rank theirs,
    // so the grid reads most-liked first across every location.
    return picks.sortedByPopularity();
  }
}
