import 'package:flutter/material.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../core/data/mock_data.dart';
import '../../core/services/analytics_service.dart';
import '../../core/services/view_mode_service.dart';
import 'feed_navigator.dart';
import 'widgets/mobile_home_layout.dart';
import 'widgets/web_home_layout.dart';

class HomeScreen extends StatefulWidget {
  final Function(String photoId)? onPhotoTap;
  final Function(String locationName)? onChatTap;

  const HomeScreen({super.key, this.onPhotoTap, this.onChatTap});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedCategoryIndex = 0;

  /// Selected location tab within the current category. null means "All".
  String? _selectedLocation;

  /// Grid or carousel. Held here, above both layouts, so it survives the
  /// browser crossing the mobile/web width breakpoint, and saved so it
  /// survives a restart.
  final _viewModeService = ViewModeService();
  PhotoViewMode _viewMode = PhotoViewMode.masonry;
  bool _viewModeChosenThisSession = false;

  /// Bumped to make both layouts drop back to the plain photo feed — out of
  /// Explore or the map, with the search cleared — when another page asks
  /// for a particular location tab.
  int _showFeedRequests = 0;

  /// The photo the last such request came from, so the carousel opens on
  /// it. Forgotten once the reader moves to another category or tab.
  String? _focusPhotoId;

  @override
  void initState() {
    super.initState();
    _viewModeService.load().then((saved) {
      // A tap on the toggle before the saved value arrives wins.
      if (!mounted || _viewModeChosenThisSession) return;
      setState(() => _viewMode = saved);
    });
    FeedNavigator.requests.addListener(_onFeedRequest);
  }

  @override
  void dispose() {
    FeedNavigator.requests.removeListener(_onFeedRequest);
    super.dispose();
  }

  /// A page above the feed (a photo's map page) asked for one location tab.
  void _onFeedRequest() {
    final target = FeedNavigator.requests.value;
    if (target == null) return;
    setState(() {
      _selectedCategoryIndex = target.categoryIndex;
      _selectedLocation = target.locationName;
      _focusPhotoId = target.photoId;
      _showFeedRequests++;
    });
  }

  void _onViewModeToggled() {
    final next = _viewMode.toggled;
    _viewModeChosenThisSession = true;
    setState(() => _viewMode = next);
    AnalyticsService.viewModeChanged(next.name);
    _viewModeService.save(next);
  }

  void _onCategoryChanged(int index) {
    if (index >= 0 && index < categories.length) {
      AnalyticsService.categorySelected(categories[index]);
    }
    setState(() {
      if (index != _selectedCategoryIndex) _focusPhotoId = null;
      _selectedCategoryIndex = index;
      // Location tabs belong to a category, so start the new one on "All".
      _selectedLocation = null;
    });
  }

  void _onLocationChanged(String? location) {
    AnalyticsService.locationSelected(location);
    setState(() {
      if (location != _selectedLocation) _focusPhotoId = null;
      _selectedLocation = location;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      mobileLayout: MobileHomeLayout(
        selectedCategoryIndex: _selectedCategoryIndex,
        onCategoryChanged: _onCategoryChanged,
        selectedLocation: _selectedLocation,
        onLocationChanged: _onLocationChanged,
        viewMode: _viewMode,
        onViewModeToggled: _onViewModeToggled,
        showFeedRequests: _showFeedRequests,
        focusPhotoId: _focusPhotoId,
        onPhotoTap: widget.onPhotoTap,
        onChatTap: widget.onChatTap,
      ),
      webLayout: WebHomeLayout(
        selectedCategoryIndex: _selectedCategoryIndex,
        onCategoryChanged: _onCategoryChanged,
        selectedLocation: _selectedLocation,
        onLocationChanged: _onLocationChanged,
        viewMode: _viewMode,
        onViewModeToggled: _onViewModeToggled,
        showFeedRequests: _showFeedRequests,
        focusPhotoId: _focusPhotoId,
        onPhotoTap: widget.onPhotoTap,
        onChatTap: widget.onChatTap,
      ),
    );
  }
}
