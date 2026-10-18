import 'package:flutter/material.dart';

import '../../../core/services/view_mode_service.dart';

/// Switches the feed between the grid and the carousel.
///
/// The icon shows the layout a tap will switch *to*, the way a play/pause
/// button does, and the tooltip says so in words.
class ViewModeToggleButton extends StatelessWidget {
  final PhotoViewMode mode;
  final VoidCallback onPressed;
  final double iconSize;

  const ViewModeToggleButton({
    super.key,
    required this.mode,
    required this.onPressed,
    this.iconSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    final toCarousel = mode == PhotoViewMode.masonry;
    return IconButton(
      icon: Icon(
        toCarousel ? Icons.view_carousel_outlined : Icons.grid_view,
        size: iconSize,
      ),
      tooltip: toCarousel ? 'Switch to carousel view' : 'Switch to grid view',
      onPressed: onPressed,
    );
  }
}
