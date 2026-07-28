import 'package:flutter/material.dart';
import '../../core/data/mock_data.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../chat/widgets/chat_widgets.dart';

class PictureChatScreen extends StatelessWidget {
  final String photoId;
  final VoidCallback? onClose;

  const PictureChatScreen({super.key, required this.photoId, this.onClose});

  PhotoPost get _photo =>
      MockPhotos.hikingPhotos.firstWhere((p) => p.id == photoId, orElse: () => MockPhotos.hikingPhotos.first);

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      mobileLayout: _MobilePictureChat(photo: _photo, onClose: onClose),
      webLayout: _WebPictureModal(photo: _photo, onClose: onClose),
    );
  }
}

// ── Mobile: 40% photo / 60% comments ──────────────────

class _MobilePictureChat extends StatelessWidget {
  final PhotoPost photo;
  final VoidCallback? onClose;

  const _MobilePictureChat({required this.photo, this.onClose});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Photo section (~40%)
            Expanded(
              flex: 4,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    photo.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: AppColors.surfaceVariant,
                      child: const Icon(Icons.landscape, size: 64, color: AppColors.textSecondary),
                    ),
                  ),
                  // Back button
                  Positioned(
                    top: 8,
                    left: 8,
                    child: CircleAvatar(
                      backgroundColor: Colors.black45,
                      radius: 18,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white, size: 18),
                        onPressed: onClose ?? () => Navigator.pop(context),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  // Location pill
                  Positioned(
                    bottom: 12,
                    left: 12,
                    child: LocationPill(
                      locationName: '${photo.location.name} · ${photo.location.region ?? ''}',
                    ),
                  ),
                ],
              ),
            ),

            // User info row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  UserAvatar(
                    initials: photo.user.initials,
                    color: photo.user.avatarColor,
                    size: 36,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          photo.user.name,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          photo.user.role ?? '',
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  HeartCount(count: photo.heartCount),
                  const SizedBox(width: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.chat_bubble_outline, size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 3),
                      Text(
                        photo.commentCount.toString(),
                        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Comments section (~60%)
            Expanded(
              flex: 6,
              child: Column(
                children: [
                  // Comments header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Comments & Discussion',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.hiking, size: 14, color: AppColors.primary),
                              const SizedBox(width: 4),
                              Text(
                                photo.location.category,
                                style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      '${MockComments.photoComments.length} comments · ${photo.location.name}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Comments list
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: MockComments.photoComments.length,
                      itemBuilder: (context, index) {
                        return _CommentTile(comment: MockComments.photoComments[index]);
                      },
                    ),
                  ),

                  // Input
                  const ChatInputBar(hintText: 'Add a comment...'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Web: Modal with photo left, comments right ────────

class _WebPictureModal extends StatelessWidget {
  final PhotoPost photo;
  final VoidCallback? onClose;

  const _WebPictureModal({required this.photo, this.onClose});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black26,
      body: Center(
        child: Container(
          width: 860,
          height: 520,
          margin: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 32,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              // Left: Photo
              Expanded(
                flex: 5,
                child: Column(
                  children: [
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            photo.imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: AppColors.surfaceVariant,
                              child: const Icon(Icons.landscape, size: 64, color: AppColors.textSecondary),
                            ),
                          ),
                          Positioned(
                            top: 12,
                            left: 12,
                            child: LocationPill(
                              locationName: '${photo.location.name} · ${photo.location.region ?? ''}',
                            ),
                          ),
                        ],
                      ),
                    ),
                    // User info bar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      color: Colors.white,
                      child: Row(
                        children: [
                          UserAvatar(
                            initials: photo.user.initials,
                            color: photo.user.avatarColor,
                            size: 32,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(photo.user.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                Text(
                                  '${photo.user.role ?? "Contributor"} · Bay Area',
                                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Text(
                              'Follow',
                              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                          ),
                          const SizedBox(width: 12),
                          HeartCount(count: photo.heartCount),
                          const SizedBox(width: 12),
                          const Icon(Icons.bookmark_outline, size: 20, color: AppColors.textSecondary),
                          const SizedBox(width: 8),
                          const Icon(Icons.share_outlined, size: 20, color: AppColors.textSecondary),
                          const SizedBox(width: 8),
                          const Icon(Icons.chat_bubble_outline, size: 18, color: AppColors.textSecondary),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const VerticalDivider(width: 1),

              // Right: Comments
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    // Close button
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: onClose ?? () => Navigator.pop(context),
                      ),
                    ),

                    // Comments
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: MockComments.photoComments.length,
                        itemBuilder: (context, index) {
                          return _CommentTile(comment: MockComments.photoComments[index]);
                        },
                      ),
                    ),

                    // Input
                    const ChatInputBar(hintText: 'Add a comment...'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared Comment Tile ───────────────────────────────

class _CommentTile extends StatelessWidget {
  final Comment comment;

  const _CommentTile({required this.comment});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(
            initials: comment.user.initials,
            color: comment.user.avatarColor,
            size: 30,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  comment.user.name,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  comment.text,
                  style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      comment.timestamp,
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                    if (comment.heartCount > 0) ...[
                      const SizedBox(width: 10),
                      HeartCount(count: comment.heartCount, iconSize: 12),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
