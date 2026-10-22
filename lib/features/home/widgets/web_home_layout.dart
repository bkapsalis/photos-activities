import 'package:flutter/material.dart';
import '../../../core/constants/constants.dart';
import '../../../core/data/mock_data.dart';
import '../../../core/models/models.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/services/firestore_service.dart';
import '../../../core/utils/photo_sorting.dart';
import '../../explore/explore_view.dart';
import '../../map/photo_map_view.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/live_data.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../../../core/widgets/upload_access.dart';
import '../../auth/account_button.dart';
import '../../auth/upgrade_account_screen.dart';
import '../../../core/utils/permissions.dart';
import '../../../core/services/view_mode_service.dart';
import 'delete_location_dialog.dart';
import 'location_tab_bar.dart';
import 'map_toggle.dart';
import 'photo_feed_view.dart';
import 'photo_masonry_grid.dart';
import 'batch_upload_dialog.dart';
import 'upload_photo_dialog.dart';
import 'view_mode_toggle_button.dart';

/// Which of the three web views is showing.
enum _WebView { feed, explore, map }

class WebHomeLayout extends StatefulWidget {
  final int selectedCategoryIndex;
  final ValueChanged<int> onCategoryChanged;
  final String? selectedLocation;
  final ValueChanged<String?> onLocationChanged;
  final PhotoViewMode viewMode;
  final VoidCallback onViewModeToggled;

  /// Changes whenever another page asks for a particular location tab (see
  /// FeedNavigator). The tab itself arrives in [selectedCategoryIndex] and
  /// [selectedLocation]; this is the cue to show the plain feed for it.
  final int showFeedRequests;

  /// The photo the carousel should centre on for that request.
  final String? focusPhotoId;
  final Function(String photoId)? onPhotoTap;
  final Function(String locationName)? onChatTap;

  const WebHomeLayout({
    super.key,
    required this.selectedCategoryIndex,
    required this.onCategoryChanged,
    required this.selectedLocation,
    required this.onLocationChanged,
    required this.viewMode,
    required this.onViewModeToggled,
    this.showFeedRequests = 0,
    this.focusPhotoId,
    this.onPhotoTap,
    this.onChatTap,
  });

  @override
  State<WebHomeLayout> createState() => _WebHomeLayoutState();
}

class _WebHomeLayoutState extends State<WebHomeLayout> {
  String _searchQuery = '';
  final _searchController = TextEditingController();

  /// Lets the title act as a Home button, as it does on mobile.
  final _feedScrollController = ScrollController();

  /// Web has no bottom nav, so Explore and Map are toggles in the top bar
  /// rather than tabs. A single value rather than one flag each means the
  /// two can never be switched on at the same time.
  _WebView _view = _WebView.feed;

  /// Set while the map is showing: where a second click on Map goes back to.
  MapReturnPoint<_WebView>? _mapReturn;

  @override
  void didUpdateWidget(WebHomeLayout old) {
    super.didUpdateWidget(old);
    if (widget.showFeedRequests != old.showFeedRequests) _showRequestedFeed();
  }

  /// Shows the location tab another page asked for: out of Explore or the
  /// map and back to the feed, with nothing hiding its photos. Like the Home
  /// reset, except the requested tab is kept rather than set back to "All".
  void _showRequestedFeed() {
    _view = _WebView.feed;
    _mapReturn = null;
    _searchQuery = '';
    _searchController.clear();
    // With a photo to return to, the grid scrolls to it; otherwise the top.
    _gridFocusPending = widget.focusPhotoId != null;
    if (!_gridFocusPending) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_feedScrollController.hasClients) _feedScrollController.jumpTo(0);
      });
    }
  }

  /// Set by a request that names a photo; cleared once the grid has scrolled
  /// to it, so later rebuilds leave the reader's scroll position alone.
  bool _gridFocusPending = false;

  @override
  void dispose() {
    _searchController.dispose();
    _feedScrollController.dispose();
    super.dispose();
  }

  /// Mirrors the mobile Home tab: clear the search, drop back to the "All"
  /// location tab, and scroll the grid to the top.
  void _resetToHome() {
    setState(() {
      _view = _WebView.feed;
      _mapReturn = null;
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

  void _openMap() {
    setState(() {
      _mapReturn = MapReturnPoint(
        view: _view,
        categoryIndex: widget.selectedCategoryIndex,
        location: widget.selectedLocation,
        search: _searchController.text,
      );
      _view = _WebView.map;
    });
  }

  /// The second click on Map: back to the view, category, location tab and
  /// search the map was opened from, as on mobile.
  void _leaveMap() {
    final back = _mapReturn;
    if (back == null) return _resetToHome();
    setState(() {
      _view = back.view;
      _mapReturn = null;
      _searchController.text = back.search;
      _searchQuery = back.search.trim().toLowerCase();
    });
    if (widget.selectedCategoryIndex != back.categoryIndex) {
      widget.onCategoryChanged(back.categoryIndex);
    }
    if (widget.selectedLocation != back.location) {
      widget.onLocationChanged(back.location);
    }
  }

  /// A different location tab starts at its top; the grid is kept between
  /// tabs, scroll position and all.
  void _changeLocation(String? location) {
    widget.onLocationChanged(location);
    if (_feedScrollController.hasClients) _feedScrollController.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final currentCategory = categories[widget.selectedCategoryIndex];
    final firestoreService = FirestoreService();

    // Hidden views kept alive under the map; only the one it was opened from.
    final mapFrom = _view == _WebView.map ? _mapReturn?.view : null;
    final keepExplore =
        _view == _WebView.explore || mapFrom == _WebView.explore;
    final keepFeed = _view == _WebView.feed || mapFrom == _WebView.feed;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Top navigation bar
          _WebTopNav(
            selectedCategoryIndex: widget.selectedCategoryIndex,
            onCategoryChanged: widget.onCategoryChanged,
            onChatTap: widget.onChatTap,
            searchController: _searchController,
            onSearchChanged: (val) =>
                setState(() => _searchQuery = val.trim().toLowerCase()),
            onHomeTap: () {
              AnalyticsService.screen('home');
              _resetToHome();
            },
            view: _view,
            viewMode: widget.viewMode,
            onViewModeToggled: widget.onViewModeToggled,
            onExploreTap: () {
              setState(() {
                _view = _view == _WebView.explore
                    ? _WebView.feed
                    : _WebView.explore;
                _mapReturn = null;
              });
              AnalyticsService.screen(
                _view == _WebView.explore ? 'explore' : 'home',
              );
            },
            onMapTap: () {
              _view == _WebView.map ? _leaveMap() : _openMap();
              AnalyticsService.screen(switch (_view) {
                _WebView.map => 'map',
                _WebView.explore => 'explore',
                _WebView.feed => 'home',
              });
            },
          ),
          const Divider(height: 1),

          // Guest prompt — hidden once the account is registered
          const GuestBanner(),

          // Body: Explore, or the usual Sidebar + Grid.
          // Explore spans every category, so the category-scoped sidebar is
          // replaced rather than kept alongside it.
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_view != _WebView.explore)
                  KeyedSubtree(
                    key: const ValueKey('feed'),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left sidebar — location list with chat access
                        _WebSidebar(
                          selectedCategory: currentCategory,
                          firestoreService: firestoreService,
                          onChatTap: widget.onChatTap,
                        ),
                        const VerticalDivider(width: 1),

                        // Main photo grid
                        Expanded(
                          child: CategoryPhotosBuilder(
                            category: currentCategory,
                            builder: (context, categoryPhotos) {
                              // Tabs are built from every photo in the category so the
                              // strip stays stable while searching inside one location.
                              final tabs = LocationTabs.fromPhotos(
                                categoryPhotos,
                              );
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
                                          p.location.name
                                              .toLowerCase()
                                              .contains(_searchQuery) ||
                                          (p.location.region
                                                  ?.toLowerCase()
                                                  .contains(_searchQuery) ??
                                              false),
                                    )
                                    .toList();
                              }

                              // Most-liked first, within whichever tab is showing.
                              photos = photos.sortedByPopularity();

                              return _WebPhotoGrid(
                                category: currentCategory,
                                photos: photos,
                                searchQuery: _searchQuery,
                                tabs: tabs,
                                activeLocation: activeLocation,
                                onLocationChanged: _changeLocation,
                                onPhotoTap: widget.onPhotoTap,
                                onChatTap: widget.onChatTap,
                                scrollController: _feedScrollController,
                                showMap: _view == _WebView.map,
                                keepFeed: keepFeed,
                                viewMode: widget.viewMode,
                                focusPhotoId: widget.focusPhotoId,
                                showFeedRequests: widget.showFeedRequests,
                                gridFocusPhotoId: _gridFocusPending
                                    ? widget.focusPhotoId
                                    : null,
                                onGridFocusDone: () =>
                                    _gridFocusPending = false,
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                if (keepExplore)
                  KeyedSubtree(
                    key: const ValueKey('explore'),
                    child: Offstage(
                      offstage: _view != _WebView.explore,
                      child: TickerMode(
                        enabled: _view == _WebView.explore,
                        child: ExploreView(onPhotoTap: widget.onPhotoTap),
                      ),
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
  final Function(String locationName)? onChatTap;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;

  /// Tapping the title/logo returns the feed to its default view.
  final VoidCallback onHomeTap;

  /// Which view is showing, and how to toggle each alternative.
  final _WebView view;
  final VoidCallback onExploreTap;
  final VoidCallback onMapTap;

  /// Grid or carousel for the photo feed.
  final PhotoViewMode viewMode;
  final VoidCallback onViewModeToggled;

  const _WebTopNav({
    required this.selectedCategoryIndex,
    required this.onCategoryChanged,
    this.onChatTap,
    required this.searchController,
    required this.onSearchChanged,
    required this.onHomeTap,
    required this.view,
    required this.onExploreTap,
    required this.onMapTap,
    required this.viewMode,
    required this.onViewModeToggled,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppSizing.webTopNavHeight,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      color: Colors.white,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Logo + title, tappable as a Home button like any site header.
            InkWell(
              onTap: onHomeTap,
              borderRadius: BorderRadius.circular(8),
              child: Semantics(
                button: true,
                label: "Bill's Bay Area, return to home",
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.landscape,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bill\'s Bay Area',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            'Fun Activities',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
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

            const SizedBox(width: 24),

            // Explore and Map toggles — the web stand-ins for those tabs on
            // the mobile bottom bar, in the same order.
            IconButton(
              icon: Icon(
                view == _WebView.explore
                    ? Icons.explore
                    : Icons.explore_outlined,
                size: 22,
                color: view == _WebView.explore ? AppColors.primary : null,
              ),
              tooltip: view == _WebView.explore
                  ? 'Back to all photos'
                  : 'Explore',
              onPressed: onExploreTap,
            ),
            IconButton(
              icon: Icon(
                view == _WebView.map ? Icons.map : Icons.map_outlined,
                size: 22,
                color: view == _WebView.map ? AppColors.primary : null,
              ),
              tooltip: view == _WebView.map ? 'Back to all photos' : 'Map',
              onPressed: onMapTap,
            ),
            // Grid/carousel only means something while the feed is showing.
            if (view == _WebView.feed)
              ViewModeToggleButton(
                mode: viewMode,
                onPressed: onViewModeToggled,
                iconSize: 22,
              ),
            const SizedBox(width: 8),

            // Search
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: SizedBox(
                height: 36,
                width: 220,
                child: TextField(
                  controller: searchController,
                  onChanged: onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Search locations...',
                    hintStyle: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
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
            const SizedBox(width: 12),

            // Upload buttons. Web has no floating action button; these are the
            // equivalent, and they are hidden on the map for the same reason:
            // nothing on that page says which place an upload would belong to.
            // Only for those allowed to upload; see UploadAccess.
            if (view != _WebView.map)
              UploadAccess(
                builder: (context, canUpload) => !canUpload
                    ? const SizedBox.shrink()
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ActionButton(
                            icon: Icons.camera_alt,
                            label: 'Camera',
                            onTap: () => UploadPhotoDialog.showCamera(
                              context,
                              initialCategory:
                                  categories[selectedCategoryIndex],
                            ),
                          ),
                          const SizedBox(width: 8),
                          _ActionButton(
                            icon: Icons.photo_library,
                            label: 'Upload',
                            onTap: () => UploadPhotoDialog.showGallery(
                              context,
                              initialCategory:
                                  categories[selectedCategoryIndex],
                            ),
                          ),
                          const SizedBox(width: 8),
                          _ActionButton(
                            icon: Icons.folder_open,
                            label: 'Folder',
                            onTap: () => BatchUploadDialog.show(
                              context,
                              initialCategory:
                                  categories[selectedCategoryIndex],
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                      ),
              ),
            const AccountButton(size: 34),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.textPrimary),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
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
  final FirestoreService firestoreService;
  final Function(String locationName)? onChatTap;

  const _WebSidebar({
    required this.selectedCategory,
    required this.firestoreService,
    this.onChatTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSizing.webSidebarWidth,
      color: AppColors.sidebarBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        selectedCategory,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'LOCATION CHATS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),

          // Location list from Firestore
          Expanded(
            child: LiveData<List<String>>(
              identity: selectedCategory,
              stream: () =>
                  firestoreService.streamDistinctLocations(selectedCategory),
              errorMessage: 'Locations could not be loaded.',
              // The sidebar is narrow: a line and a retry, not a full panel.
              errorBuilder: (context, retry) => TextButton.icon(
                onPressed: retry,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Locations did not load. Retry'),
              ),
              builder: (context, locations) {
                if (locations.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'Upload photos to see locations here.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: locations.length,
                  itemBuilder: (context, index) {
                    final locName = locations[index];
                    return ListTile(
                      dense: true,
                      leading: const Icon(
                        Icons.chat_bubble_outline,
                        size: 18,
                        color: AppColors.primary,
                      ),
                      title: Text(
                        locName,
                        style: const TextStyle(fontSize: 13),
                      ),
                      onTap: () => onChatTap?.call(locName),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _WebPhotoGrid extends StatelessWidget {
  final String category;
  final List<PhotoPost> photos;
  final String searchQuery;
  final LocationTabs tabs;
  final String? activeLocation;
  final ValueChanged<String?> onLocationChanged;
  final Function(String photoId)? onPhotoTap;
  final Function(String locationName)? onChatTap;
  final ScrollController? scrollController;

  /// Show the photos as map pins instead of a grid. The location tabs stay
  /// above either way, so the map follows whatever is selected — the same
  /// arrangement the mobile Map tab uses.
  final bool showMap;

  /// Keep the photos alive, hidden, under the map; see [FeedUnderMap].
  final bool keepFeed;

  /// Grid or carousel, when the photos are not on the map.
  final PhotoViewMode viewMode;

  /// The photo the carousel should centre on, and the request it came with.
  final String? focusPhotoId;
  final int showFeedRequests;

  /// The photo the grid should scroll to, once; see PhotoMasonryGrid.
  final String? gridFocusPhotoId;
  final VoidCallback? onGridFocusDone;

  const _WebPhotoGrid({
    required this.category,
    required this.photos,
    this.searchQuery = '',
    required this.tabs,
    required this.activeLocation,
    required this.onLocationChanged,
    this.onPhotoTap,
    this.onChatTap,
    this.scrollController,
    this.showMap = false,
    this.keepFeed = true,
    this.viewMode = PhotoViewMode.masonry,
    this.focusPhotoId,
    this.showFeedRequests = 0,
    this.gridFocusPhotoId,
    this.onGridFocusDone,
  });

  IconData get _categoryIcon {
    switch (category.toLowerCase()) {
      case 'museums - historic sites':
        return Icons.museum;
      default:
        return Icons.hiking;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Row(
            children: [
              Icon(_categoryIcon, color: AppColors.primary, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      searchQuery.isNotEmpty
                          ? 'Showing results for "$searchQuery"'
                          : activeLocation ?? 'Your uploaded photos',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Location tabs for this category
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: LocationTabBar(
            tabs: tabs,
            selectedLocation: activeLocation,
            onLocationChanged: onLocationChanged,
            // Bulk delete spans other people's photos: moderators only.
            onDeleteLocation: !isAdmin()
                ? null
                : (name) => DeleteLocationDialog.show(
                    context,
                    category: category,
                    locationName: name,
                    photoCount: tabs.counts[name] ?? 0,
                  ),
          ),
        ),
        const SizedBox(height: 20),

        // Content area
        Expanded(
          child: FeedUnderMap(
            showMap: showMap,
            keepFeed: keepFeed,
            map: PhotoMapView(photos: photos, onPhotoTap: onPhotoTap),
            feed: photos.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          searchQuery.isNotEmpty
                              ? Icons.search_off
                              : Icons.add_a_photo,
                          size: 64,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          searchQuery.isNotEmpty
                              ? 'No photos match "$searchQuery"'
                              : 'No photos yet in ${activeLocation ?? category}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (searchQuery.isEmpty)
                          UploadAccess(
                            builder: (context, canUpload) => !canUpload
                                ? const SizedBox.shrink()
                                : const Padding(
                                    padding: EdgeInsets.only(top: 8),
                                    child: Text(
                                      'Upload your first photo using the buttons above!',
                                      style: TextStyle(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                          ),
                      ],
                    ),
                  )
                : PhotoFeedView(
                    mode: viewMode,
                    focusPhotoId: focusPhotoId,
                    focusRequest: showFeedRequests,
                    photos: photos,
                    onPhotoTap: onPhotoTap,
                    horizontalPadding: 24,
                    masonry: LayoutBuilder(
                      builder: (context, constraints) {
                        final crossAxisCount = constraints.maxWidth > 1200
                            ? 5
                            : constraints.maxWidth > 900
                            ? 4
                            : constraints.maxWidth > 600
                            ? 3
                            : 2;
                        return PhotoMasonryGrid(
                          photos: photos,
                          onPhotoTap: onPhotoTap,
                          controller: scrollController!,
                          physics: const AlwaysScrollableScrollPhysics(),
                          crossAxisCount: crossAxisCount,
                          spacing: 16,
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                          focusPhotoId: gridFocusPhotoId,
                          onFocusDone: onGridFocusDone,
                        );
                      },
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
