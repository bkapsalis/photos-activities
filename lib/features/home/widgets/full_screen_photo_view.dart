import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/models/models.dart';
import '../../../core/widgets/app_network_image.dart';

/// One photo, edge to edge on black, pinch- or scroll-zoomable.
///
/// Opened from the carousel's large image, which shares its [heroTag], so the
/// picture grows into place and shrinks back on the way out. Closing pops this
/// route and nothing else, which leaves the carousel exactly as it was — same
/// photo selected, same thumbnail centred.
class FullScreenPhotoView extends StatelessWidget {
  final PhotoPost photo;

  const FullScreenPhotoView({super.key, required this.photo});

  static String heroTag(String photoId) => 'carousel-photo-$photoId';

  static Future<void> open(BuildContext context, PhotoPost photo) {
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (_, _, _) => FullScreenPhotoView(photo: photo),
        // A fade lets the Hero carry the motion; a slide would fight it.
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    void close() => Navigator.of(context).maybePop();

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
              InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Hero(
                  tag: heroTag(photo.id),
                  child: AppNetworkImage(
                    photo.imageUrl,
                    fit: BoxFit.contain,
                    onDark: true,
                  ),
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
