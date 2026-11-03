import 'package:flutter/material.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_colors.dart';

/// The distinct location names inside a category, with a photo count each.
///
/// Derived from the photos already streamed for the category so the tab strip
/// costs no extra Firestore subscription.
class LocationTabs {
  final List<String> names;
  final Map<String, int> counts;
  final int totalCount;

  const LocationTabs({
    required this.names,
    required this.counts,
    required this.totalCount,
  });

  factory LocationTabs.fromPhotos(List<PhotoPost> photos) {
    final counts = <String, int>{};
    for (final photo in photos) {
      final name = photo.location.name.trim();
      if (name.isEmpty) continue;
      counts[name] = (counts[name] ?? 0) + 1;
    }
    final names = counts.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return LocationTabs(
      names: names,
      counts: counts,
      totalCount: photos.length,
    );
  }

  /// Falls back to "All" when the selected name is no longer present — e.g. the
  /// last photo for that location was deleted or re-categorized.
  String? resolve(String? selected) =>
      (selected != null && counts.containsKey(selected)) ? selected : null;
}

/// A scrollable tab strip: "All" followed by one tab per location name.
///
/// [selectedLocation] of null means the "All" tab.
class LocationTabBar extends StatefulWidget {
  final LocationTabs tabs;
  final String? selectedLocation;
  final ValueChanged<String?> onLocationChanged;

  /// Deletes every photo in one location. Null hides the control entirely.
  ///
  /// Only the selected tab shows its delete icon. Putting one on every tab
  /// would sit an irreversible action a few pixels from the tab beside it, in
  /// a strip people scrub through to browse.
  final ValueChanged<String>? onDeleteLocation;

  const LocationTabBar({
    super.key,
    required this.tabs,
    required this.selectedLocation,
    required this.onLocationChanged,
    this.onDeleteLocation,
  });

  @override
  State<LocationTabBar> createState() => _LocationTabBarState();
}

class _LocationTabBarState extends State<LocationTabBar>
    with TickerProviderStateMixin {
  late TabController _controller;

  int get _tabCount => widget.tabs.names.length + 1;

  int get _selectedIndex {
    final selected = widget.selectedLocation;
    if (selected == null) return 0;
    final index = widget.tabs.names.indexOf(selected);
    return index == -1 ? 0 : index + 1;
  }

  @override
  void initState() {
    super.initState();
    _controller = _buildController();
  }

  TabController _buildController() {
    return TabController(
      length: _tabCount,
      vsync: this,
      initialIndex: _selectedIndex,
    )..addListener(_handleTabSelection);
  }

  void _handleTabSelection() {
    if (_controller.indexIsChanging) return;
    final index = _controller.index;
    final location = index == 0 ? null : widget.tabs.names[index - 1];
    if (location != widget.selectedLocation) {
      widget.onLocationChanged(location);
    }
  }

  @override
  void didUpdateWidget(covariant LocationTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A location was added or removed — the controller has to be rebuilt
    // because TabController.length is immutable.
    if (_controller.length != _tabCount) {
      _controller
        ..removeListener(_handleTabSelection)
        ..dispose();
      _controller = _buildController();
    } else if (_controller.index != _selectedIndex) {
      _controller.index = _selectedIndex;
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleTabSelection)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tabs.names.isEmpty) return const SizedBox.shrink();

    return TabBar(
      controller: _controller,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      labelColor: AppColors.primary,
      unselectedLabelColor: AppColors.textSecondary,
      indicatorColor: AppColors.primary,
      indicatorSize: TabBarIndicatorSize.label,
      indicatorWeight: 3,
      dividerColor: AppColors.divider,
      labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      tabs: [
        // "All" never offers a delete: it would mean every photo in the
        // category, which is not what a per-location control should do.
        Tab(height: 42, text: 'All (${widget.tabs.totalCount})'),
        ...widget.tabs.names.map((name) {
          final count = widget.tabs.counts[name] ?? 0;
          final isSelected = name == widget.selectedLocation;
          final onDelete = widget.onDeleteLocation;
          return Tab(
            height: 42,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$name ($count)'),
                if (isSelected && onDelete != null && count > 0) ...[
                  const SizedBox(width: 6),
                  _DeleteTabButton(
                    locationName: name,
                    onPressed: () => onDelete(name),
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }
}

/// The delete affordance inside a selected tab.
///
/// [HitTestBehavior.opaque] keeps the tap from falling through to the tab
/// itself, which would re-select the tab instead of opening the confirmation.
class _DeleteTabButton extends StatelessWidget {
  final String locationName;
  final VoidCallback onPressed;

  const _DeleteTabButton({required this.locationName, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Delete all photos in $locationName',
      child: Tooltip(
        message: 'Delete all photos in $locationName',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
            child: Icon(
              Icons.delete_outline,
              size: 17,
              color: AppColors.heartRed,
            ),
          ),
        ),
      ),
    );
  }
}
