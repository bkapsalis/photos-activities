import 'package:flutter/material.dart';
import '../../../core/constants/constants.dart';
import '../../../core/data/mock_data.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/shared_widgets.dart';
import 'photo_card.dart';

class WebHomeLayout extends StatelessWidget {
  final int selectedCategoryIndex;
  final ValueChanged<int> onCategoryChanged;
  final Function(String photoId)? onPhotoTap;
  final Function(String locationId)? onChatTap;

  const WebHomeLayout({
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
      body: Column(
        children: [
          // Top navigation bar
          _WebTopNav(
            selectedCategoryIndex: selectedCategoryIndex,
            onCategoryChanged: onCategoryChanged,
            onChatTap: onChatTap,
          ),
          const Divider(height: 1),

          // Body: Sidebar + Grid
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left sidebar
                _WebSidebar(selectedCategory: categories[selectedCategoryIndex]),
                const VerticalDivider(width: 1),

                // Main photo grid
                Expanded(
                  child: _WebPhotoGrid(
                    photos: MockPhotos.hikingPhotos,
                    onPhotoTap: onPhotoTap,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WebTopNav extends StatelessWidget {
  final int selectedCategoryIndex;
  final ValueChanged<int> onCategoryChanged;
  final Function(String locationId)? onChatTap;

  const _WebTopNav({
    required this.selectedCategoryIndex,
    required this.onCategoryChanged,
    this.onChatTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppSizing.webTopNavHeight,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      color: Colors.white,
      child: Row(
        children: [
          // Logo + title
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.landscape, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bill\'s Fun Things To Do',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              Text(
                'In The Bay Area!',
                style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(width: 24),

          // Category pills
          ...List.generate(categories.length, (i) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: CategoryChip(
                label: categories[i],
                isSelected: i == selectedCategoryIndex,
                onTap: () => onCategoryChanged(i),
              ),
            );
          }),

          const Spacer(),

          // Search
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: SizedBox(
                height: 36,
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search Bay Area spots, trails, venues...',
                    hintStyle: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: AppColors.divider),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: AppColors.divider),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Actions
          Stack(
            children: [
              IconButton(icon: const Icon(Icons.notifications_outlined, size: 22), onPressed: () {}),
              Positioned(
                right: 8, top: 8,
                child: Container(
                  width: 14, height: 14,
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  child: const Center(child: Text('3', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold))),
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
          _ActionButton(
            icon: Icons.chat_bubble_outline,
            label: 'Community Chat',
            color: AppColors.primary,
            onTap: () => onChatTap?.call('hiking'),
          ),
          const SizedBox(width: 8),
          _ActionButton(
            icon: Icons.chat_outlined,
            label: 'Open Chat',
            onTap: () => onChatTap?.call('hiking'),
          ),
          const SizedBox(width: 8),
          _ActionButton(
            icon: Icons.add,
            label: 'Upload',
            onTap: () {},
          ),
          const SizedBox(width: 12),
          const UserAvatar(initials: 'BK', color: AppColors.primary, size: 34),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _ActionButton({required this.icon, required this.label, this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isColored = color != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isColored ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: isColored ? null : Border.all(color: AppColors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isColored ? Colors.white : AppColors.textPrimary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isColored ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WebSidebar extends StatelessWidget {
  final String selectedCategory;

  const _WebSidebar({required this.selectedCategory});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSizing.webSidebarWidth,
      color: AppColors.sidebarBackground,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category header
            Row(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(
                  selectedCategory,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Text(
              '6 photo spots',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),

            // Stats
            const Text(
              'COMMUNITY STATS',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary, letterSpacing: 0.5),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _StatBlock(value: '${CommunityStats.likes}', label: 'Likes'),
                const SizedBox(width: 24),
                _StatBlock(value: '${CommunityStats.photos}', label: 'Photos'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _StatBlock(value: '${CommunityStats.spots}', label: 'Spots'),
              ],
            ),
            const SizedBox(height: 24),

            // Locations
            const Text(
              'LOCATIONS',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary, letterSpacing: 0.5),
            ),
            Row(
              children: [
                TextButton(
                  onPressed: () {},
                  child: Text('All Locations', style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            ...MockLocations.hiking.map((loc) => _LocationRow(location: loc)),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),
            _SidebarLink(icon: Icons.trending_up, label: 'Trending'),
            _SidebarLink(icon: Icons.favorite_outline, label: 'Favorites'),
          ],
        ),
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  final String value;
  final String label;

  const _StatBlock({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _LocationRow extends StatelessWidget {
  final Location location;

  const _LocationRow({required this.location});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 6, height: 6,
            decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              location.name,
              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              location.postCount.toString(),
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarLink extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SidebarLink({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

class _WebPhotoGrid extends StatelessWidget {
  final List<PhotoPost> photos;
  final Function(String photoId)? onPhotoTap;

  const _WebPhotoGrid({required this.photos, this.onPhotoTap});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.hiking, color: AppColors.primary, size: 28),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hiking', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    Text(
                      'Discover amazing spots shared by local guides · All Locations',
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              _ActionButton(icon: Icons.filter_list, label: 'Filter', onTap: () {}),
              const SizedBox(width: 8),
              _ActionButton(icon: Icons.chat_outlined, label: 'Open Chat', onTap: () {}),
              const SizedBox(width: 8),
              _ActionButton(icon: Icons.add, label: 'Upload', onTap: () {}),
            ],
          ),
          const SizedBox(height: 24),

          // Photo grid
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth > 900 ? 4 : (constraints.maxWidth > 600 ? 3 : 2);
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: photos.map((photo) {
                  final cardWidth = (constraints.maxWidth - (crossAxisCount - 1) * 16) / crossAxisCount;
                  return SizedBox(
                    width: cardWidth,
                    child: PhotoCard(
                      photo: photo,
                      onTap: () => onPhotoTap?.call(photo.id),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
