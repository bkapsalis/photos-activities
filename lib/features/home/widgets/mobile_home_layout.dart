import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../../../core/data/mock_data.dart';
import '../../../core/models/models.dart';
import '../../../core/services/firestore_service.dart';
import '../../../core/utils/photo_sorting.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../../auth/account_button.dart';
import '../../auth/upgrade_account_screen.dart';
import '../../profile/profile_screen.dart';
import '../../explore/explore_view.dart';
import '../../map/photo_map_view.dart';
import 'delete_location_dialog.dart';
import 'location_tab_bar.dart';
import 'photo_card.dart';
import 'batch_upload_dialog.dart';
import 'upload_photo_dialog.dart';

class MobileHomeLayout extends StatefulWidget {
  final int selectedCategoryIndex;
  final ValueChanged<int> onCategoryChanged;
  final String? selectedLocation;
  final ValueChanged<String?> onLocationChanged;
  final Function(String photoId)? onPhotoTap;
  final Function(String locationId)? onChatTap;

  const MobileHomeLayout({
    super.key,
    required this.selectedCategoryIndex,
    required this.onCategoryChanged,
    required this.selectedLocation,
    required this.onLocationChanged,
    this.onPhotoTap,
    this.onChatTap,
  });

  @override
  State<MobileHomeLayout> createState() => _MobileHomeLayoutState();
}

class _MobileHomeLayoutState extends State<MobileHomeLayout> {
  String _searchQuery = '';
  final _searchController = TextEditingController();

  /// Lets the Home tab scroll the feed back to the top.
  final _feedScrollController = ScrollController();

  /// Home is the only tab with a screen of its own. Profile opens as a pushed
  /// route and Explore/Map have nothing to show yet, so this stays 0 except
  /// while one of those is genuinely selected.
  int _navIndex = 0;

  @override
  void dispose() {
    _searchController.dispose();
    _feedScrollController.dispose();
    super.dispose();
  }

  /// Tapping Home returns the feed to its default view rather than doing
  /// nothing: clear the search, drop back to the "All" location tab, and
  /// scroll to the top. Whichever of those is already true is simply a no-op.
  void _resetToHome() {
    setState(() {
      _navIndex = 0;
      _searchQuery = '';
      _searchController.clear();
    });
    widget.onLocationChanged(null);
    if (_feedScrollController.hasClients) {
      _feedScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentCategory = categories[widget.selectedCategoryIndex];
    final firestoreService = FirestoreService();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _navIndex == 1
            ? ExploreView(onPhotoTap: widget.onPhotoTap)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // App bar area
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          // The title doubles as a Home button, the way a site's
                          // logo usually does. Same reset as the Home tab.
                          child: InkWell(
                            onTap: _resetToHome,
                            borderRadius: BorderRadius.circular(8),
                            child: Semantics(
                              button: true,
                              label: "Bill's Bay Area, return to home",
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                  horizontal: 4,
                                ),
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
                                      "Bill's Bay Area",
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            // Location chat list button
                            IconButton(
                              icon: const Icon(Icons.forum_outlined, size: 24),
                              tooltip: 'Location Chats',
                              onPressed: () => _showLocationChats(
                                context,
                                currentCategory,
                                firestoreService,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const AccountButton(size: 36),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Guest prompt — hidden once the account is registered
                  const GuestBanner(),
                  const SizedBox(height: 8),

                  // Search bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(
                        () => _searchQuery = val.trim().toLowerCase(),
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search locations...',
                        hintStyle: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppColors.divider),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppColors.divider),
                        ),
                        filled: true,
                        fillColor: AppColors.surfaceVariant,
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
                          isSelected: index == widget.selectedCategoryIndex,
                          onTap: () => widget.onCategoryChanged(index),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Photo feed (Firestore Stream)
                  Expanded(
                    child: StreamBuilder<List<PhotoPost>>(
                      stream: firestoreService.streamPhotosByCategory(
                        currentCategory,
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        final categoryPhotos = snapshot.data ?? [];

                        // Tabs are built from every photo in the category so the strip
                        // stays stable while searching inside one location.
                        final tabs = LocationTabs.fromPhotos(categoryPhotos);
                        final activeLocation = tabs.resolve(
                          widget.selectedLocation,
                        );

                        var photos = activeLocation == null
                            ? categoryPhotos
                            : categoryPhotos
                                  .where(
                                    (p) =>
                                        p.location.name.trim() ==
                                        activeLocation,
                                  )
                                  .toList();

                        // Apply search filter
                        if (_searchQuery.isNotEmpty) {
                          photos = photos
                              .where(
                                (p) =>
                                    p.location.name.toLowerCase().contains(
                                      _searchQuery,
                                    ) ||
                                    (p.location.region?.toLowerCase().contains(
                                          _searchQuery,
                                        ) ??
                                        false),
                              )
                              .toList();
                        }

                        // Most-liked first, within whichever tab is showing.
                        photos = photos.sortedByPopularity();

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LocationTabBar(
                              tabs: tabs,
                              selectedLocation: activeLocation,
                              onLocationChanged: widget.onLocationChanged,
                              onDeleteLocation: (name) =>
                                  DeleteLocationDialog.show(
                                    context,
                                    category: currentCategory,
                                    locationName: name,
                                    photoCount: tabs.counts[name] ?? 0,
                                  ),
                            ),
                            const SizedBox(height: 12),
                            Expanded(
                              child: _navIndex == 2
                                  ? PhotoMapView(
                                      photos: photos,
                                      onPhotoTap: widget.onPhotoTap,
                                    )
                                  : photos.isEmpty
                                  ? _EmptyFeed(
                                      searchQuery: _searchQuery,
                                      scopeLabel:
                                          activeLocation ?? currentCategory,
                                    )
                                  : _MasonryFeed(
                                      photos: photos,
                                      onPhotoTap: widget.onPhotoTap,
                                      scrollController: _feedScrollController,
                                    ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),

      // FAB with 3 upload options. Only the feed offers uploading: Explore is
      // a read-only shuffle, and on the map the button sits over the tiles and
      // pins without belonging to the place being looked at.
      floatingActionButton: _navIndex != 0
          ? null
          : FloatingActionButton(
              onPressed: () => _showUploadOptions(context, currentCategory),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              child: const Icon(Icons.add, size: 28),
            ),

      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        onDestinationSelected: (index) {
          switch (index) {
            case 0:
              _resetToHome();
            case 1:
              setState(() => _navIndex = 1);
            case 2:
              setState(() => _navIndex = 2);
            case 3:
              // Profile is a pushed route, so the bar stays on Home behind it.
              ProfileScreen.show(context);
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Explore',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  void _showUploadOptions(BuildContext context, String category) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Upload Photo',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppColors.primary),
              title: const Text('Take a Photo'),
              subtitle: const Text('Open camera and upload'),
              onTap: () {
                Navigator.pop(ctx);
                UploadPhotoDialog.showCamera(
                  context,
                  initialCategory: category,
                );
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library,
                color: AppColors.primary,
              ),
              title: const Text('Upload from Device'),
              subtitle: const Text('Pick one image from gallery'),
              onTap: () {
                Navigator.pop(ctx);
                UploadPhotoDialog.showGallery(
                  context,
                  initialCategory: category,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_open, color: AppColors.primary),
              title: const Text('Upload from Folder'),
              subtitle: const Text('Select a folder or pick multiple files'),
              onTap: () {
                Navigator.pop(ctx);
                BatchUploadDialog.show(context, initialCategory: category);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showLocationChats(
    BuildContext context,
    String category,
    FirestoreService firestoreService,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.forum, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      '$category — Location Chats',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: StreamBuilder<List<String>>(
                  stream: firestoreService.streamDistinctLocations(category),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final locations = snapshot.data ?? [];
                    if (locations.isEmpty) {
                      return const Center(
                        child: Text(
                          'No locations yet. Upload photos to create location chats!',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      );
                    }
                    return ListView.builder(
                      controller: scrollController,
                      itemCount: locations.length,
                      itemBuilder: (context, index) {
                        final locName = locations[index];
                        // Use a sanitized locationId for Firestore chat path
                        final locId = locName.toLowerCase().replaceAll(
                          RegExp(r'[^a-z0-9]'),
                          '_',
                        );
                        return ListTile(
                          leading: const Icon(
                            Icons.chat_bubble_outline,
                            color: AppColors.primary,
                          ),
                          title: Text(locName),
                          subtitle: Text(
                            category,
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.pop(ctx);
                            widget.onChatTap?.call(locId);
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MasonryFeed extends StatelessWidget {
  final List<PhotoPost> photos;
  final Function(String photoId)? onPhotoTap;
  final ScrollController? scrollController;

  const _MasonryFeed({
    required this.photos,
    this.onPhotoTap,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return MasonryGridView.count(
      controller: scrollController,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: photos.length,
      itemBuilder: (context, index) {
        final photo = photos[index];
        return PhotoCard(photo: photo, onTap: () => onPhotoTap?.call(photo.id));
      },
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  final String searchQuery;
  final String scopeLabel;

  const _EmptyFeed({required this.searchQuery, required this.scopeLabel});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              searchQuery.isNotEmpty ? Icons.search_off : Icons.add_a_photo,
              size: 64,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              searchQuery.isNotEmpty
                  ? 'No photos match "$searchQuery"'
                  : 'No photos yet in $scopeLabel',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            if (searchQuery.isEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Tap + to upload your first photo!',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
