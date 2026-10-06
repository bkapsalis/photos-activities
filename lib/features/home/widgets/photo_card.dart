import 'package:flutter/material.dart';
import '../../../core/models/models.dart';
import '../../../core/services/firestore_service.dart';
import '../../../core/services/photo_deletion_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/permissions.dart';
import '../../../core/widgets/shared_widgets.dart';
import 'edit_photo_dialog.dart';

class PhotoCard extends StatelessWidget {
  final PhotoPost photo;
  final VoidCallback? onTap;

  const PhotoCard({super.key, required this.photo, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            // Photo – sized to the image's real aspect ratio so the masonry
            // grid cell matches its shape and nothing gets cropped off.
            _AutoAspectImage(
              imageUrl: photo.imageUrl,
              fallbackAspectRatio: (photo.aspectRatio > 0) ? photo.aspectRatio : 1.2,
            ),

            // Location pill (top-left)
            Positioned(
              top: 10,
              left: 10,
              child: LocationPill(locationName: photo.location.name),
            ),

            // Edit / Delete Menu (top-right), for the owner or a moderator
            // only; firestore.rules refuse anyone else.
            if (canModify(photo.user.id))
            Positioned(
              top: 6,
              right: 6,
              child: PopupMenuButton<String>(
                icon: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.more_vert, color: Colors.white, size: 16),
                ),
                onSelected: (value) async {
                  if (value == 'edit') {
                    EditPhotoDialog.show(context, photo);
                  } else if (value == 'delete') {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete Photo?'),
                        content: const Text('Are you sure you want to delete this photo post?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: TextButton.styleFrom(foregroundColor: Colors.red),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      // Removes the image file and comments too, not just the
                      // document — a document-only delete leaves both stranded.
                      final result = await PhotoDeletionService().deleteOne(
                        photoId: photo.id,
                        imageUrl: photo.imageUrl,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              result.failed > 0
                                  ? 'Could not delete that photo.'
                                  : 'Photo deleted',
                            ),
                          ),
                        );
                      }
                    }
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 18, color: AppColors.textPrimary),
                        SizedBox(width: 8),
                        Text('Edit Photo'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 18, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Delete Photo', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // User + hearts (bottom)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.55)],
                  ),
                ),
                child: Row(
                  children: [
                    UserAvatar(
                      initials: photo.user.initials,
                      color: photo.user.avatarColor,
                      size: 24,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        photo.user.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        if (photo.id.isNotEmpty) {
                          FirestoreService().incrementHeartCount(photo.id);
                        }
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.favorite, color: Colors.white.withValues(alpha: 0.9), size: 14),
                          const SizedBox(width: 3),
                          Text(
                            photo.heartCount.toString(),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sizes itself to the network image's real width/height so masonry grid
/// cells match the photo's true shape instead of a stale/placeholder ratio,
/// so [BoxFit.cover] never has to crop content away.
class _AutoAspectImage extends StatefulWidget {
  final String imageUrl;
  final double fallbackAspectRatio;

  const _AutoAspectImage({
    required this.imageUrl,
    required this.fallbackAspectRatio,
  });

  @override
  State<_AutoAspectImage> createState() => _AutoAspectImageState();
}

class _AutoAspectImageState extends State<_AutoAspectImage> {
  double? _aspectRatio;
  ImageStream? _imageStream;
  late final ImageStreamListener _listener;

  @override
  void initState() {
    super.initState();
    _listener = ImageStreamListener(_onImageResolved, onError: (_, __) {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImage();
  }

  void _resolveImage() {
    final newStream = NetworkImage(widget.imageUrl).resolve(
      createLocalImageConfiguration(context),
    );
    if (newStream.key == _imageStream?.key) return;
    _imageStream?.removeListener(_listener);
    _imageStream = newStream;
    _imageStream!.addListener(_listener);
  }

  void _onImageResolved(ImageInfo info, bool _) {
    final ratio = info.image.width / info.image.height;
    if (mounted && ratio != _aspectRatio) {
      setState(() => _aspectRatio = ratio);
    }
  }

  @override
  void dispose() {
    _imageStream?.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: _aspectRatio ?? widget.fallbackAspectRatio,
      child: Image.network(
        widget.imageUrl,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          color: AppColors.surfaceVariant,
          child: const Icon(Icons.landscape, size: 48, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}
