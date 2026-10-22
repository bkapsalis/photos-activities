import 'package:flutter/material.dart';

import '../services/like_service.dart';
import '../theme/app_colors.dart';
import '../utils/user_action.dart';

/// A photo's heart: filled once the reader has liked it. Tapping likes the
/// photo, and tapping again takes the like back.
class LikeButton extends StatefulWidget {
  final String photoId;
  final int count;

  /// Drawn over a photo, in white, rather than in the heart's red.
  final bool onImage;

  const LikeButton({
    super.key,
    required this.photoId,
    required this.count,
    this.onImage = false,
  });

  @override
  State<LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<LikeButton> {
  /// Set while a like is on its way: a second tap before it lands would ask
  /// for the same like twice, which the rules rightly refuse.
  bool _busy = false;

  Future<void> _toggle(bool liked) async {
    setState(() => _busy = true);
    await runUserAction(
      context,
      () => LikeService.setLiked(widget.photoId, liked: !liked),
      failureMessage: liked
          ? 'Your like was not removed. Please try again.'
          : 'Your like did not go through. Please try again.',
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: LikeService.likedPhotoIds,
      builder: (context, likedIds, _) {
        final liked = likedIds.contains(widget.photoId);
        return LikeView(
          liked: liked,
          count: widget.count,
          onImage: widget.onImage,
          onTap: _busy || widget.photoId.isEmpty ? null : () => _toggle(liked),
        );
      },
    );
  }
}

/// How a like looks, separate from where it comes from, so it can be tested
/// without Firebase.
class LikeView extends StatelessWidget {
  final bool liked;
  final int count;
  final bool onImage;
  final VoidCallback? onTap;

  const LikeView({
    super.key,
    required this.liked,
    required this.count,
    this.onImage = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = onImage
        ? Colors.white.withValues(alpha: 0.9)
        : AppColors.heartRed;
    return Semantics(
      button: true,
      toggled: liked,
      label: liked ? 'Liked, $count likes' : 'Like, $count likes',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          // A comfortable target for a thumb, around a small heart.
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                liked ? Icons.favorite : Icons.favorite_border,
                color: color,
                size: onImage ? 14 : 16,
              ),
              const SizedBox(width: 3),
              Text(
                count.toString(),
                style: TextStyle(
                  color: onImage ? color : AppColors.textSecondary,
                  fontSize: onImage ? 12 : 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
