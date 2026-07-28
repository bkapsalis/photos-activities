import 'package:flutter/material.dart';
import '../../core/widgets/shared_widgets.dart';
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

  void _onCategoryChanged(int index) {
    setState(() => _selectedCategoryIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      mobileLayout: MobileHomeLayout(
        selectedCategoryIndex: _selectedCategoryIndex,
        onCategoryChanged: _onCategoryChanged,
        onPhotoTap: widget.onPhotoTap,
        onChatTap: widget.onChatTap,
      ),
      webLayout: WebHomeLayout(
        selectedCategoryIndex: _selectedCategoryIndex,
        onCategoryChanged: _onCategoryChanged,
        onPhotoTap: widget.onPhotoTap,
        onChatTap: widget.onChatTap,
      ),
    );
  }
}
