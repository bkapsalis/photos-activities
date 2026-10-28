import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/models/models.dart';
import '../../../core/widgets/app_network_image.dart';

/// One photo, edge to edge on black, pinch- or scroll-zoomable.
///
/// Opened by [TapToEnlarge]: from the carousel's large image, which shares
/// its [sharedTag] so the picture grows into place and shrinks back on the
/// way out, and from a photo's comments page, which fades. Closing pops this
/// route and nothing else, which leaves the page underneath exactly as it
/// was — in the carousel, same photo selected, same thumbnail centred.
/// Tapping anywhere on the photo closes it, as does Back or Esc; dragging
/// and pinching still pan and zoom, because a tap only counts when the
/// finger lifts without moving.
class FullScreenPhotoView extends StatelessWidget {
  final PhotoPost photo;

  /// Shared with the image that opened this, to animate between the two.
  /// Null where nothing should fly: the comments page can sit on top of a
  /// carousel already showing this photo under the same tag.
  final String? sharedTag;

  const FullScreenPhotoView({super.key, required this.photo, this.sharedTag});

  static String heroTag(String photoId) => 'carousel-photo-$photoId';

  static Future<void> open(
    BuildContext context,
    PhotoPost photo, {
    String? sharedTag,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (_, _, _) =>
            FullScreenPhotoView(photo: photo, sharedTag: sharedTag),
        // A fade lets the Hero carry the motion; a slide would fight it.
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    void close() => Navigator.of(context).maybePop();
    final image = AppNetworkImage(
      photo.imageUrl,
      fit: BoxFit.contain,
      onDark: true,
    );
    final tag = sharedTag;

    return CallbackShortcuts(
      // Esc closes, as anyone using the web build will expect of a viewer.
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): close},
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          // expand, not the default loose fit: a Scaffold body is only
          // loosely constrained, and a loose Stack shrinks to its one sized
          // child — the back button — leaving the photo a 56px sliver.
          body: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                // opaque: the black around a letterboxed photo closes too.
                behavior: HitTestBehavior.opaque,
                onTap: close,
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: tag == null ? image : Hero(tag: tag, child: image),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Back',
                      color: Colors.white,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                      ),
                      onPressed: close,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens [photo] full screen when [child] is tapped, and says so with a
/// small "Tap to Enlarge" label in one corner.
///
/// [child] is the image as the page shows it, stretched to fill the space
/// this is given. [sharedTag], when set, wraps it in a Hero so it grows into
/// the full-screen view rather than fading in.
class TapToEnlarge extends StatelessWidget {
  final PhotoPost photo;
  final Widget child;
  final String? sharedTag;

  /// Where the label sits, clear of anything else drawn over the photo.
  /// Top right by default: the bottom right is where every uploaded photo
  /// carries its photographer's watermark.
  final Alignment hintAlignment;

  const TapToEnlarge({
    super.key,
    required this.photo,
    required this.child,
    this.sharedTag,
    this.hintAlignment = Alignment.topRight,
  });

  static const hintLabel = 'Tap to Enlarge';

  @override
  Widget build(BuildContext context) {
    final tag = sharedTag;
    return MouseRegion(
      cursor: SystemMouseCursors.zoomIn,
      child: Semantics(
        button: true,
        label: 'Open ${photo.location.name} photo full screen',
        child: GestureDetector(
          onTap: () => FullScreenPhotoView.open(context, photo, sharedTag: tag),
          child: Stack(
            fit: StackFit.expand,
            children: [
              tag == null ? child : Hero(tag: tag, child: child),
              Align(
                alignment: hintAlignment,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: _EnlargeHint(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EnlargeHint extends StatelessWidget {
  const _EnlargeHint();

  @override
  Widget build(BuildContext context) {
    // The button's own label already says what a tap does.
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.zoom_out_map, size: 14, color: Colors.white),
              SizedBox(width: 5),
              Text(
                TapToEnlarge.hintLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
