import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'core/config/env_config.dart';
import 'features/home/home_screen.dart';
import 'features/location_chat/location_chat_screen.dart';
import 'features/picture_chat/picture_chat_screen.dart';

class BillsBayAreaApp extends StatelessWidget {
  const BillsBayAreaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: EnvConfig.instance.title,
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: EnvConfig.instance.isDev,
      home: const _AppShell(),
    );
  }
}

class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  void _openLocationChat(String locationId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LocationChatScreen(
          locationId: locationId,
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  void _openPictureChat(String photoId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PictureChatScreen(
          photoId: photoId,
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return HomeScreen(
      onPhotoTap: _openPictureChat,
      onChatTap: _openLocationChat,
    );
  }
}
