import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services/view_mode_service.dart';

/// The name the toggle shows when touched, held or hovered.
const viewModeToggleName = 'The Alondra Toggle';

/// Switches the feed between the grid and the carousel.
///
/// The icon shows the layout a tap will switch *to*, the way a play/pause
/// button does. Its tooltip is the toggle's name, shown on a tap as well as
/// on a press and hold or a hover; screen readers hear what it does instead.
class ViewModeToggleButton extends StatefulWidget {
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
  State<ViewModeToggleButton> createState() => _ViewModeToggleButtonState();
}

class _ViewModeToggleButtonState extends State<ViewModeToggleButton> {
  final _tooltip = GlobalKey<TooltipState>();

  /// Hides the name a tap showed: shown that way it would stay up until the
  /// next touch anywhere.
  Timer? _hide;

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  void _pressed() {
    widget.onPressed();
    _tooltip.currentState?.ensureTooltipVisible();
    _hide?.cancel();
    _hide = Timer(
      const Duration(milliseconds: 1500),
      Tooltip.dismissAllToolTips,
    );
  }

  @override
  Widget build(BuildContext context) {
    final toCarousel = widget.mode == PhotoViewMode.masonry;
    return Tooltip(
      key: _tooltip,
      message: viewModeToggleName,
      excludeFromSemantics: true,
      child: IconButton(
        icon: Icon(
          toCarousel ? Icons.view_carousel_outlined : Icons.grid_view,
          size: widget.iconSize,
          semanticLabel: toCarousel
              ? 'Switch to carousel view'
              : 'Switch to grid view',
        ),
        onPressed: _pressed,
      ),
    );
  }
}
