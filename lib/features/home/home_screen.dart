import 'package:flutter/material.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../core/data/mock_data.dart';
import '../../core/services/analytics_service.dart';
import 'widgets/mobile_home_layout.dart';
import 'widgets/web_home_layout.dart';

class HomeScreen extends StatefulWidget {
  final Function(String photoId)? onPhotoTap;
  final Function(String locationId)? onChatTap;

  const HomeScreen({super.key, this.onPhotoTap, this.onChatTap});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedCategoryIndex = 0;

  /// Selected location tab within the current category. null means "All".
  String? _selectedLocation;

  void _onCategoryChanged(int index) {
    if (index >= 0 && index < categories.length) {
      AnalyticsService.categorySelected(categories[index]);
    }
    setState(() {
      _selectedCategoryIndex = index;
      // Location tabs belong to a category, so start the new one on "All".
      _selectedLocation = null;
    });
  }

  void _onLocationChanged(String? location) {
    AnalyticsService.locationSelected(location);
    setState(() => _selectedLocation = location);
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      mobileLayout: MobileHomeLayout(
        selectedCategoryIndex: _selectedCategoryIndex,
        onCategoryChanged: _onCategoryChanged,
        selectedLocation: _selectedLocation,
        onLocationChanged: _onLocationChanged,
        onPhotoTap: widget.onPhotoTap,
        onChatTap: widget.onChatTap,
      ),
      webLayout: WebHomeLayout(
        selectedCategoryIndex: _selectedCategoryIndex,
        onCategoryChanged: _onCategoryChanged,
        selectedLocation: _selectedLocation,
        onLocationChanged: _onLocationChanged,
        onPhotoTap: widget.onPhotoTap,
        onChatTap: widget.onChatTap,
      ),
    );
  }
}
