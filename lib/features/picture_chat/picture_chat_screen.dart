import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import '../../core/data/mock_data.dart';
import '../../core/models/models.dart';
import '../../core/services/firestore_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../chat/widgets/chat_widgets.dart';
import '../home/widgets/edit_photo_dialog.dart';

class PictureChatScreen extends StatelessWidget {
  final String photoId;
  final VoidCallback? onClose;

  const PictureChatScreen({super.key, required this.photoId, this.onClose});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PhotoPost?>(
      future: FirestoreService().getPhoto(photoId),
      builder: (context, snapshot) {
        final photo = snapshot.data ??
            MockPhotos.hikingPhotos.firstWhere(
              (p) => p.id == photoId,
              orElse: () => MockPhotos.hikingPhotos.first,
            );

        return ResponsiveLayout(
          mobileLayout: _MobilePictureChat(photo: photo, onClose: onClose),
          webLayout: _WebPictureModal(photo: photo, onClose: onClose),
        );
      },
    );
  }
}

// ── Mobile: 40% photo / 60% comments ──────────────────

class _MobilePictureChat extends StatelessWidget {
  final PhotoPost photo;
  final VoidCallback? onClose;

  const _MobilePictureChat({required this.photo, this.onClose});

  void _addComment(String text) async {
    final currentUser = auth.FirebaseAuth.instance.currentUser;
    final userProfile = currentUser != null
        ? UserProfile.fromFirebaseUser(currentUser)
        : MockUsers.me;
    final comment = Comment(
      id: '',
      user: userProfile,
      text: text,
      timestamp: 'Just now',
      heartCount: 0,
    );
    await FirestoreService().addComment(photo.id, comment);
  }

  @override
  Widget build(BuildContext context) {
    final firestoreService = FirestoreService();

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

            // User info row & Photo Actions
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
                          photo.user.role ?? 'Contributor',
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      if (photo.id.isNotEmpty) {
                        firestoreService.incrementHeartCount(photo.id);
                      }
                    },
                    child: HeartCount(count: photo.heartCount),
                  ),
                  const SizedBox(width: 12),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20, color: AppColors.textSecondary),
                    onSelected: (val) async {
                      if (val == 'edit') {
                        EditPhotoDialog.show(context, photo);
                      } else if (val == 'delete') {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Delete Photo?'),
                            content: const Text('Are you sure you want to delete this photo post?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                style: TextButton.styleFrom(foregroundColor: Colors.red),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await firestoreService.deletePhoto(photo.id);
                          if (context.mounted) {
                            (onClose ?? () => Navigator.pop(context))();
                          }
                        }
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 18),
                            SizedBox(width: 8),
                            Text('Edit Photo'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 18, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Delete Photo', style: TextStyle(color: Colors.red)),
                          ],
                        ),
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
                              const Icon(Icons.landscape, size: 14, color: AppColors.primary),
                              const SizedBox(width: 4),
                              Text(
                                photo.location.category.isNotEmpty ? photo.location.category : 'Spot',
                                style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Comments stream
                  Expanded(
                    child: StreamBuilder<List<Comment>>(
                      stream: firestoreService.streamComments(photo.id),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        final comments = snapshot.data ?? [];
                        if (comments.isEmpty) {
                          return const Center(
                            child: Text('No comments yet. Leave a comment! 💬',
                                style: TextStyle(color: AppColors.textSecondary)),
                          );
                        }

                        return ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: comments.length,
                          itemBuilder: (context, index) {
                            return _CommentTile(photoId: photo.id, comment: comments[index]);
                          },
                        );
                      },
                    ),
                  ),

                  // Input
                  ChatInputBar(
                    hintText: 'Add a comment...',
                    onSend: _addComment,
                  ),
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

  void _addComment(String text) async {
    final currentUser = auth.FirebaseAuth.instance.currentUser;
    final userProfile = currentUser != null
        ? UserProfile.fromFirebaseUser(currentUser)
        : MockUsers.me;
    final comment = Comment(
      id: '',
      user: userProfile,
      text: text,
      timestamp: 'Just now',
      heartCount: 0,
    );
    await FirestoreService().addComment(photo.id, comment);
  }

  @override
  Widget build(BuildContext context) {
    final firestoreService = FirestoreService();

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
                          GestureDetector(
                            onTap: () {
                              if (photo.id.isNotEmpty) {
                                firestoreService.incrementHeartCount(photo.id);
                              }
                            },
                            child: HeartCount(count: photo.heartCount),
                          ),
                          const SizedBox(width: 12),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert, size: 20, color: AppColors.textSecondary),
                            onSelected: (val) async {
                              if (val == 'edit') {
                                EditPhotoDialog.show(context, photo);
                              } else if (val == 'delete') {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Delete Photo?'),
                                    content: const Text('Are you sure you want to delete this photo post?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, true),
                                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                                        child: const Text('Delete'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  await firestoreService.deletePhoto(photo.id);
                                  if (context.mounted) {
                                    (onClose ?? () => Navigator.pop(context))();
                                  }
                                }
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit, size: 18),
                                    SizedBox(width: 8),
                                    Text('Edit Photo'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete, size: 18, color: Colors.red),
                                    SizedBox(width: 8),
                                    Text('Delete Photo', style: TextStyle(color: Colors.red)),
                                  ],
                                ),
                              ),
                            ],
                          ),
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

                    // Comments stream
                    Expanded(
                      child: StreamBuilder<List<Comment>>(
                        stream: firestoreService.streamComments(photo.id),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }

                          final comments = snapshot.data ?? [];
                          if (comments.isEmpty) {
                            return const Center(
                              child: Text('No comments yet. Leave a comment! 💬',
                                  style: TextStyle(color: AppColors.textSecondary)),
                            );
                          }

                          return ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: comments.length,
                            itemBuilder: (context, index) {
                              return _CommentTile(photoId: photo.id, comment: comments[index]);
                            },
                          );
                        },
                      ),
                    ),

                    // Input
                    ChatInputBar(
                      hintText: 'Add a comment...',
                      onSend: _addComment,
                    ),
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
  final String photoId;
  final Comment comment;

  const _CommentTile({required this.photoId, required this.comment});

  void _showEditCommentDialog(BuildContext context) {
    final controller = TextEditingController(text: comment.text);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Comment ✏️'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Update your comment...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newText = controller.text.trim();
              if (newText.isNotEmpty && comment.id.isNotEmpty) {
                await FirestoreService().updateComment(photoId, comment.id, newText);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      comment.user.name,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    if (comment.id.isNotEmpty)
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_horiz, size: 16, color: AppColors.textSecondary),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onSelected: (val) async {
                          if (val == 'edit') {
                            _showEditCommentDialog(context);
                          } else if (val == 'delete') {
                            await FirestoreService().deleteComment(photoId, comment.id);
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit, size: 16),
                                SizedBox(width: 6),
                                Text('Edit Comment'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, size: 16, color: Colors.red),
                                SizedBox(width: 6),
                                Text('Delete Comment', style: TextStyle(color: Colors.red)),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
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
