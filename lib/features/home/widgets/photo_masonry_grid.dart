import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../../core/models/models.dart';
import '../../../core/theme/app_colors.dart';
import 'photo_card.dart';

/// The staggered photo grid, shared by the mobile and web feeds — they differ
/// only in column count, spacing and padding, which are passed in.
///
/// It can also bring one photo into view ([focusPhotoId]): used when the
/// reader comes back from that photo's map page, so they land on the photo
/// they were looking at rather than the top of the tab.
class PhotoMasonryGrid extends StatefulWidget {
  final List<PhotoPost> photos;
  final Function(String photoId)? onPhotoTap;
  final ScrollController controller;
  final ScrollPhysics physics;
  final int crossAxisCount;
  final double spacing;
  final EdgeInsets padding;

  /// Scroll to this photo once and outline it briefly. One-shot: the owner
  /// clears it when [onFocusDone] is called, so a later rebuild of the grid
  /// does not yank the reader back to it.
  final String? focusPhotoId;
  final VoidCallback? onFocusDone;

  /// Replaces [PhotoCard] in widget tests, where it cannot run (it asks
  /// Firebase who may edit the photo).
  @visibleForTesting
  final Widget Function(PhotoPost photo, VoidCallback onTap)? tileBuilder;

  const PhotoMasonryGrid({
    super.key,
    required this.photos,
    required this.controller,
    required this.physics,
    required this.crossAxisCount,
    required this.spacing,
    required this.padding,
    this.onPhotoTap,
    this.focusPhotoId,
    this.onFocusDone,
    this.tileBuilder,
  });

  @override
  State<PhotoMasonryGrid> createState() => _PhotoMasonryGridState();
}

class _PhotoMasonryGridState extends State<PhotoMasonryGrid> {
  final _focusKey = GlobalKey();

  /// How long the outline stays on the photo returned to, and how thick it
  /// is — long and bold enough to find at a glance in a busy grid.
  static const highlightFor = Duration(seconds: 5);
  static const outlineWidth = 8.0;

  /// The photo being outlined right now, if any.
  String? _highlightId;
  Timer? _highlightTimer;

  @override
  void dispose() {
    _highlightTimer?.cancel();
    super.dispose();
  }

  void _highlight(String id) {
    _highlightTimer?.cancel();
    setState(() => _highlightId = id);
    _highlightTimer = Timer(highlightFor, () {
      if (mounted && _highlightId == id) setState(() => _highlightId = null);
    });
  }

  @override
  void initState() {
    super.initState();
    if (widget.focusPhotoId != null) _scheduleFocus();
  }

  @override
  void didUpdateWidget(PhotoMasonryGrid old) {
    super.didUpdateWidget(old);
    if (widget.focusPhotoId != null &&
        widget.focusPhotoId != old.focusPhotoId) {
      _scheduleFocus();
    }
  }

  void _scheduleFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToFocus());
  }

  Future<void> _nextFrame() => WidgetsBinding.instance.endOfFrame;

  /// The grid only builds tiles near the screen, and tiles are as tall as
  /// their photos, so the target's position cannot be worked out in advance.
  /// Step down a screen at a time until its tile exists, then scroll it into
  /// view properly.
  Future<void> _scrollToFocus() async {
    final id = widget.focusPhotoId;
    if (!mounted || id == null) return;
    if (!widget.photos.any((p) => p.id == id)) {
      widget.onFocusDone?.call();
      return;
    }

    for (var step = 0; step < 200; step++) {
      if (!mounted) return;
      final tile = _focusKey.currentContext;
      if (tile != null && tile.mounted) {
        _highlight(id);
        await Scrollable.ensureVisible(
          tile,
          alignment: 0.15,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
        widget.onFocusDone?.call();
        // Photos above may finish loading and change height, nudging the
        // tile; settle it back into view once they have.
        await Future<void>.delayed(const Duration(milliseconds: 700));
        final settled = _focusKey.currentContext;
        if (mounted && settled != null && settled.mounted) {
          await Scrollable.ensureVisible(
            settled,
            alignment: 0.15,
            duration: const Duration(milliseconds: 200),
          );
        }
        return;
      }

      final controller = widget.controller;
      if (!controller.hasClients) {
        await _nextFrame();
        continue;
      }
      final position = controller.position;
      if (position.pixels >= position.maxScrollExtent) break;
      controller.jumpTo(
        (position.pixels + position.viewportDimension).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
      await _nextFrame();
    }
    widget.onFocusDone?.call();
  }

  @override
  Widget build(BuildContext context) {
    return MasonryGridView.count(
      controller: widget.controller,
      physics: widget.physics,
      crossAxisCount: widget.crossAxisCount,
      mainAxisSpacing: widget.spacing,
      crossAxisSpacing: widget.spacing,
      padding: widget.padding,
      itemCount: widget.photos.length,
      itemBuilder: (context, index) {
        final photo = widget.photos[index];
        void onTap() => widget.onPhotoTap?.call(photo.id);
        final tile =
            widget.tileBuilder?.call(photo, onTap) ??
            PhotoCard(photo: photo, onTap: onTap);
        if (photo.id != widget.focusPhotoId && photo.id != _highlightId) {
          return tile;
        }
        return KeyedSubtree(
          key: _focusKey,
          child: _Highlight(on: photo.id == _highlightId, child: tile),
        );
      },
    );
  }
}

/// A brief coloured outline that fades, marking the photo just returned to.
class _Highlight extends StatelessWidget {
  final bool on;
  final Widget child;

  const _Highlight({required this.on, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: on ? 1 : 0,
              duration: const Duration(milliseconds: 400),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.primary,
                    width: _PhotoMasonryGridState.outlineWidth,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
