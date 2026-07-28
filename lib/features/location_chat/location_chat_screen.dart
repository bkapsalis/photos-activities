import 'package:flutter/material.dart';
import '../../core/data/mock_data.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../chat/widgets/chat_widgets.dart';

class LocationChatScreen extends StatelessWidget {
  final String locationId;
  final VoidCallback? onClose;

  const LocationChatScreen({super.key, required this.locationId, this.onClose});

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      mobileLayout: _MobileChatSheet(onClose: onClose),
      webLayout: _WebChatPanel(onClose: onClose),
    );
  }
}

class _MobileChatSheet extends StatelessWidget {
  final VoidCallback? onClose;

  const _MobileChatSheet({this.onClose});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: onClose ?? () => Navigator.pop(context),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Eaton Canyon Trail Chat', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text('24 members', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.more_vert), onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          // Messages
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              reverse: false,
              itemCount: MockChat.locationChat.length,
              itemBuilder: (context, index) {
                return ChatMessageBubble(message: MockChat.locationChat[index]);
              },
            ),
          ),
          // Input
          const ChatInputBar(),
        ],
      ),
    );
  }
}

class _WebChatPanel extends StatelessWidget {
  final VoidCallback? onClose;

  const _WebChatPanel({this.onClose});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Row(
        children: [
          // Photo area (left)
          Expanded(
            flex: 2,
            child: Container(
              color: AppColors.surfaceVariant,
              child: Image.network(
                'https://picsum.photos/seed/eaton/1200/800',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.landscape, size: 64, color: AppColors.textSecondary),
                ),
              ),
            ),
          ),

          // Chat panel (right)
          Container(
            width: 360,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(left: BorderSide(color: AppColors.divider)),
            ),
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.divider)),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Community Chat',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: onClose ?? () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),

                // Messages
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: MockChat.locationChat.length,
                    itemBuilder: (context, index) {
                      return ChatMessageBubble(message: MockChat.locationChat[index]);
                    },
                  ),
                ),

                // Input
                const ChatInputBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
