import 'package:flutter/material.dart';
import '../../../core/models/models.dart';
import '../../../core/services/firestore_service.dart';
import '../../../core/theme/app_colors.dart';
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
            // Photo – no forced aspect ratio; let masonry handle sizing
            Image.network(
              photo.imageUrl,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 180,
                color: AppColors.surfaceVariant,
                child: const Icon(Icons.landscape, size: 48, color: AppColors.textSecondary),
              ),
            ),

            // Location pill (top-left)
            Positioned(
              top: 10,
              left: 10,
              child: LocationPill(locationName: photo.location.name),
            ),

            // Edit / Delete Menu (top-right)
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
                      await FirestoreService().deletePhoto(photo.id);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Photo deleted')),
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
