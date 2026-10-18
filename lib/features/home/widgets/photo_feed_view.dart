import 'package:flutter/material.dart';

import '../../../core/models/models.dart';
import '../../../core/services/view_mode_service.dart';
import 'photo_carousel_view.dart';

/// Shows a tab's photos in whichever [PhotoViewMode] the reader picked.
///
/// Both layouts receive the one list the feed's Firestore stream produced, so
/// switching never refetches and the two always show the same photos. The
/// grid is handed in finished rather than built here: mobile and web lay it
/// out differently (column count, spacing, scroll controller), and this is
/// only the choice between it and the carousel.
class PhotoFeedView extends StatelessWidget {
  final PhotoViewMode mode;
  final List<PhotoPost> photos;
  final Widget masonry;
  final Function(String photoId)? onPhotoTap;
  final double horizontalPadding;

  /// A photo to bring into view — the carousel centres on it — and a counter
  /// that changes with each new request, so asking for the same photo twice
  /// still moves to it. See [PhotoCarouselView.focusPhotoId].
  final String? focusPhotoId;
  final int focusRequest;

  const PhotoFeedView({
    super.key,
    required this.mode,
    required this.photos,
    required this.masonry,
    this.onPhotoTap,
    this.horizontalPadding = 16,
    this.focusPhotoId,
    this.focusRequest = 0,
  });

  @override
  Widget build(BuildContext context) {
    return switch (mode) {
      PhotoViewMode.masonry => masonry,
      PhotoViewMode.carousel => PhotoCarouselView(
        photos: photos,
        onPhotoTap: onPhotoTap,
        horizontalPadding: horizontalPadding,
        focusPhotoId: focusPhotoId,
        focusRequest: focusRequest,
      ),
    };
  }
}
