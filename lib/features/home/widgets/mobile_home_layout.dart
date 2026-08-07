import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../../../core/data/mock_data.dart';
import '../../../core/models/models.dart';
import '../../../core/services/firestore_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/shared_widgets.dart';
import 'photo_card.dart';
import 'batch_upload_dialog.dart';
import 'upload_photo_dialog.dart';

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
    final currentCategory = categories[selectedCategoryIndex];
    final firestoreService = FirestoreService();

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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Discover Bay Area',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const Text(
                          "Bill's Fun Things",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
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

            // Masonry photo feed (Firestore Stream)
            Expanded(
              child: StreamBuilder<List<PhotoPost>>(
                stream: firestoreService.streamPhotosByCategory(currentCategory),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final photos = snapshot.data ?? [];
                  if (photos.isEmpty) {
                    firestoreService.seedSampleDataIfEmpty();
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.landscape, size: 64, color: AppColors.textSecondary),
                          const SizedBox(height: 12),
                          Text('No photos yet in $currentCategory!',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: () => UploadPhotoDialog.show(context, initialCategory: currentCategory),
                            icon: const Icon(Icons.add_a_photo),
                            label: const Text('Add First Photo'),
                          ),
                        ],
                      ),
                    );
                  }

                  return _MasonryFeed(
                    photos: photos,
                    onPhotoTap: onPhotoTap,
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            builder: (ctx) => SafeArea(
              child: Wrap(
                children: [
                  ListTile(
                    leading: const Icon(Icons.add_a_photo),
                    title: const Text('Upload Single Photo'),
                    subtitle: const Text('Pick one photo from gallery or camera'),
                    onTap: () {
                      Navigator.pop(ctx);
                      UploadPhotoDialog.show(context, initialCategory: currentCategory);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.photo_library),
                    title: const Text('Batch Upload Photos'),
                    subtitle: const Text('Select up to 50 photos at once'),
                    onTap: () {
                      Navigator.pop(ctx);
                      BatchUploadDialog.show(context, initialCategory: currentCategory);
                    },
                  ),
                ],
              ),
            ),
          );
        },
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
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
    return MasonryGridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: photos.length,
      itemBuilder: (context, index) {
        final photo = photos[index];
        return PhotoCard(
          photo: photo,
          onTap: () => onPhotoTap?.call(photo.id),
        );
      },
    );
  }
}
