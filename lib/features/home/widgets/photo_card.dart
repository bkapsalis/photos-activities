import 'package:flutter/material.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/shared_widgets.dart';

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
            // Photo
            AspectRatio(
              aspectRatio: photo.aspectRatio.clamp(0.65, 1.5),
              child: Image.network(
                photo.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: AppColors.surfaceVariant,
                  child: const Icon(Icons.landscape, size: 48, color: AppColors.textSecondary),
                ),
              ),
            ),

            // Location pill (top-left)
            Positioned(
              top: 10,
              left: 10,
              child: LocationPill(locationName: photo.location.name),
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
            ),
          ],
        ),
      ),
    );
  }
}
