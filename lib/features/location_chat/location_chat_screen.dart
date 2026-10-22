import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import '../../core/models/models.dart';
import '../../core/services/firestore_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../chat/widgets/chat_widgets.dart';

class LocationChatScreen extends StatelessWidget {
  final String locationId;
  final String? locationName;
  final VoidCallback? onClose;

  const LocationChatScreen({
    super.key,
    required this.locationId,
    this.locationName,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      mobileLayout: _MobileChatSheet(
        locationId: locationId,
        locationName: locationName,
        onClose: onClose,
      ),
      webLayout: _WebChatPanel(
        locationId: locationId,
        locationName: locationName,
        onClose: onClose,
      ),
    );
  }
}

class _MobileChatSheet extends StatelessWidget {
  final String locationId;
  final String? locationName;
  final VoidCallback? onClose;

  const _MobileChatSheet({
    required this.locationId,
    this.locationName,
    this.onClose,
  });

  void _sendMessage(BuildContext context, String text) async {
    final currentUser = auth.FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to join the chat.')),
      );
      return;
    }
    final userProfile = UserProfile.fromFirebaseUser(currentUser);
    final msg = ChatMessage(
      id: '',
      user: userProfile,
      text: text,
      timestamp: 'Just now',
    );
    await FirestoreService().sendChatMessage(locationId, msg);
  }

  @override
  Widget build(BuildContext context) {
    final firestoreService = FirestoreService();
    final displayName = locationName ?? locationId;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: onClose ?? () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$displayName Chat',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Text(
              'Community Discussion',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Messages Stream
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: firestoreService.streamChatMessages(locationId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data ?? [];
                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.forum_outlined,
                          size: 48,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No messages yet in $displayName',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Be the first to chat! 💬',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    return ChatMessageBubble(message: messages[index]);
                  },
                );
              },
            ),
          ),
          // Input Bar
          ChatInputBar(
            hintText: 'Message $displayName community...',
            onSend: (text) => _sendMessage(context, text),
          ),
        ],
      ),
    );
  }
}

class _WebChatPanel extends StatelessWidget {
  final String locationId;
  final String? locationName;
  final VoidCallback? onClose;

  const _WebChatPanel({
    required this.locationId,
    this.locationName,
    this.onClose,
  });

  void _sendMessage(BuildContext context, String text) async {
    final currentUser = auth.FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to join the chat.')),
      );
      return;
    }
    final userProfile = UserProfile.fromFirebaseUser(currentUser);
    final msg = ChatMessage(
      id: '',
      user: userProfile,
      text: text,
      timestamp: 'Just now',
    );
    await FirestoreService().sendChatMessage(locationId, msg);
  }

  @override
  Widget build(BuildContext context) {
    final firestoreService = FirestoreService();
    final displayName = locationName ?? locationId;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Row(
        children: [
          // Photo area (left)
          Expanded(
            flex: 2,
            child: Container(
              color: AppColors.surfaceVariant,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.forum, size: 64, color: AppColors.primary),
                    const SizedBox(height: 16),
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Community Chat',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: AppColors.divider),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$displayName Chat',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: onClose ?? () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),

                // Messages Stream
                Expanded(
                  child: StreamBuilder<List<ChatMessage>>(
                    stream: firestoreService.streamChatMessages(locationId),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final messages = snapshot.data ?? [];
                      if (messages.isEmpty) {
                        return const Center(
                          child: Text(
                            'No messages yet. Be the first to chat! 💬',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          return ChatMessageBubble(message: messages[index]);
                        },
                      );
                    },
                  ),
                ),

                // Input Bar
                ChatInputBar(
                  hintText: 'Message $displayName community...',
                  onSend: (text) => _sendMessage(context, text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
