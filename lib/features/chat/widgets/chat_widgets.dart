import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/shared_widgets.dart';

/// The longest comment or chat message the rules accept (validText in
/// firestore.rules). Typing stops there rather than having the send refused.
const maxPostLength = 2000;

class ChatMessageBubble extends StatelessWidget {
  final ChatMessage message;

  /// Who is reading; the signed-in user unless a test supplies one.
  final String? viewerId;

  const ChatMessageBubble({super.key, required this.message, this.viewerId});

  @override
  Widget build(BuildContext context) {
    // Decided by who is reading, never by the stored message: the same
    // message is its author's own and someone else's to everyone else.
    final viewer = viewerId ?? auth.FirebaseAuth.instance.currentUser?.uid;
    final isMe = viewer != null && message.user.id == viewer;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: isMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
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
            mainAxisAlignment: isMe
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isMe
                        ? AppColors.chatBubbleMe
                        : AppColors.chatBubbleOther,
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
                      color: isMe
                          ? AppColors.chatBubbleMeText
                          : AppColors.textPrimary,
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
              mainAxisAlignment: isMe
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              children: [
                Text(
                  message.timestamp,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
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

class ChatInputBar extends StatefulWidget {
  final String hintText;

  /// Sends [text]; resolves to whether it went. A send that fails puts the
  /// text back in the box, so nothing typed is lost.
  final Future<bool> Function(String text)? onSend;

  const ChatInputBar({
    super.key,
    this.hintText = 'Message the group...',
    this.onSend,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final TextEditingController _controller = TextEditingController();

  Future<void> _handleSend() async {
    final onSend = widget.onSend;
    final text = _controller.text.trim();
    if (onSend == null || text.isEmpty) return;
    // Cleared at once, as a sent message should look: Firestore shows the
    // message straight away and only confirms it later (much later offline).
    _controller.clear();
    final sent = await onSend(text);
    // Put back a message that did not go, unless something new was typed.
    if (!sent && mounted && _controller.text.isEmpty) {
      _controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: TextField(
                  controller: _controller,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(maxPostLength),
                  ],
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _handleSend(),
                  decoration: InputDecoration(
                    hintText: widget.hintText,
                    hintStyle: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: _handleSend,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.send, color: Colors.white, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
