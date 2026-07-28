import 'package:flutter/material.dart';
import '../../../core/data/mock_data.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/shared_widgets.dart';
import 'photo_card.dart';

class MobileHomeLayout extends StatelessWidget {
  final int selectedCategoryIndex;
  final ValueChanged<int> onCategoryChanged;
  final Function(String photoId)? onPhotoTap;
  final Function(String locationId)? onChatTap;

  const MobileHomeLayout({
    super.key,
    required this.selectedCategoryIndex,
    required this.onCategoryChanged,
    this.onPhotoTap,
    this.onChatTap,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // App bar area
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Discover',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const Text(
                        'Bills Bay Area 🏔',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Stack(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chat_bubble_outline, size: 24),
                            onPressed: () => onChatTap?.call('hiking'),
                          ),
                          Positioned(
                            right: 6,
                            top: 6,
                            child: Container(
                              width: 16, height: 16,
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: const Center(
                                child: Text('3', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 4),
                      const UserAvatar(initials: 'BK', color: AppColors.primary, size: 36),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, color: AppColors.textSecondary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Search Bay Area spots...',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Category tabs
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  return CategoryChip(
                    label: categories[index],
                    isSelected: index == selectedCategoryIndex,
                    onTap: () => onCategoryChanged(index),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),

            // Masonry photo feed
            Expanded(
              child: _MasonryFeed(
                photos: MockPhotos.hikingPhotos,
                onPhotoTap: onPhotoTap,
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: const Icon(Icons.add, size: 28),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'Explore'),
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Map'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

class _MasonryFeed extends StatelessWidget {
  final List<PhotoPost> photos;
  final Function(String photoId)? onPhotoTap;

  const _MasonryFeed({required this.photos, this.onPhotoTap});

  @override
  Widget build(BuildContext context) {
    // Split photos into two columns for masonry effect
    final leftPhotos = <PhotoPost>[];
    final rightPhotos = <PhotoPost>[];
    for (int i = 0; i < photos.length; i++) {
      if (i.isEven) {
        leftPhotos.add(photos[i]);
      } else {
        rightPhotos.add(photos[i]);
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              children: leftPhotos
                  .map((p) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: PhotoCard(photo: p, onTap: () => onPhotoTap?.call(p.id)),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              children: [
                const SizedBox(height: 32), // Offset for masonry stagger
                ...rightPhotos.map((p) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: PhotoCard(photo: p, onTap: () => onPhotoTap?.call(p.id)),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
