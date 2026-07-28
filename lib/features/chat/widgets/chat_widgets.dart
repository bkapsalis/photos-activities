import 'package:flutter/material.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/shared_widgets.dart';

class ChatMessageBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatMessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(left: 44, bottom: 4),
              child: Text(
                message.user.name,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          Row(
            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMe) ...[
                UserAvatar(
                  initials: message.user.initials,
                  color: message.user.avatarColor,
                  size: 34,
                ),
                const SizedBox(width: 10),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMe ? AppColors.chatBubbleMe : AppColors.chatBubbleOther,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isMe ? 16 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 16),
                    ),
                  ),
                  child: Text(
                    message.text,
                    style: TextStyle(
                      fontSize: 14,
                      color: isMe ? AppColors.chatBubbleMeText : AppColors.textPrimary,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
              if (isMe) const SizedBox(width: 10),
            ],
          ),
          Padding(
            padding: EdgeInsets.only(
              left: isMe ? 0 : 44,
              right: isMe ? 10 : 0,
              top: 4,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
              children: [
                Text(
                  message.timestamp,
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
                if (message.reactionCount > 0) ...[
                  const SizedBox(width: 8),
                  HeartCount(count: message.reactionCount, iconSize: 13),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ChatInputBar extends StatelessWidget {
  final String hintText;

  const ChatInputBar({super.key, this.hintText = 'Message the group...'});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.photo_outlined, color: AppColors.textSecondary),
              onPressed: () {},
              iconSize: 22,
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  hintText,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.emoji_emotions_outlined, color: AppColors.textSecondary),
              onPressed: () {},
              iconSize: 22,
            ),
            Container(
              width: 38, height: 38,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send, color: Colors.white, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}
