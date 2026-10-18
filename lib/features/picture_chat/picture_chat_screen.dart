import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import '../../core/models/models.dart';
import '../../core/services/firestore_service.dart';
import '../../core/services/photo_deletion_service.dart';
import '../../core/utils/permissions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../chat/widgets/chat_widgets.dart';
import '../home/widgets/edit_photo_dialog.dart';
import '../map/photo_location_screen.dart';

class PictureChatScreen extends StatelessWidget {
  final String photoId;
  final VoidCallback? onClose;

  const PictureChatScreen({super.key, required this.photoId, this.onClose});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PhotoPost?>(
      future: FirestoreService().getPhoto(photoId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final photo = snapshot.data;
        if (photo == null) {
          return Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: onClose ?? () => Navigator.pop(context),
              ),
              title: const Text('Photo Not Found'),
            ),
            body: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.broken_image,
                    size: 64,
                    color: AppColors.textSecondary,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'This photo could not be found.',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'It may have been deleted.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          );
        }

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

  void _addComment(BuildContext context, String text) async {
    final currentUser = auth.FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      // A comment signed by a placeholder account would not belong to anyone,
      // so it could never be edited, deleted, or counted on a profile.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to add a comment.')),
      );
      return;
    }
    final userProfile = UserProfile.fromFirebaseUser(currentUser);
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
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            children: [
              // Photo section: as tall as the photo is at full width, so it is
              // never cropped, but capped so the chat always keeps 45% of the
              // screen. A photo that does not fit exactly is letterboxed.
              SizedBox(
                height: _photoHeight(constraints),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: Colors.black),
                    Image.network(
                      photo.imageUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Container(
                        color: AppColors.surfaceVariant,
                        child: const Icon(
                          Icons.landscape,
                          size: 64,
                          color: AppColors.textSecondary,
                        ),
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
                          icon: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                            size: 18,
                          ),
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
                        locationName:
                            '${photo.location.name} · ${photo.location.region ?? ''}',
                      ),
                    ),
                  ],
                ),
              ),

              // User info row & Photo Actions
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
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
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            photo.user.role ?? 'Contributor',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
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
                    // Only the owner or a moderator; firestore.rules refuse anyone else.
                    if (canModify(photo.user.id))
                      PopupMenuButton<String>(
                        icon: const Icon(
                          Icons.more_vert,
                          size: 20,
                          color: AppColors.textSecondary,
                        ),
                        onSelected: (val) async {
                          if (val == 'edit') {
                            EditPhotoDialog.show(context, photo);
                          } else if (val == 'delete') {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete Photo?'),
                                content: const Text(
                                  'Are you sure you want to delete this photo post?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.red,
                                    ),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              // Image file and comments go with it; deleting only
                              // the document would strand both.
                              await PhotoDeletionService().deleteOne(
                                photoId: photo.id,
                                imageUrl: photo.imageUrl,
                              );
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
                                Text(
                                  'Delete Photo',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),

              // Where it was taken sits between the photo and the
              // conversation. It opens an in-app map; directions are offered
              // from there. For a photo with no recorded location the button
              // shows disabled, with a line saying why.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: SizedBox(
                  width: double.infinity,
                  child: MapLocationButton(photo: photo),
                ),
              ),

              const Divider(height: 1),

              // Comments section: whatever the photo leaves, at least 45%.
              Expanded(
                child: Column(
                  children: [
                    // Comments header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      // Both children must be able to give ground: a long
                      // category such as "Museums - Historic Sites" overflowed
                      // this row when neither could shrink.
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Comments & Discussion',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.landscape,
                                    size: 14,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      photo.location.category.isNotEmpty
                                          ? photo.location.category
                                          : 'Spot',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
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
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          final comments = snapshot.data ?? [];
                          if (comments.isEmpty) {
                            return const Center(
                              child: Text(
                                'No comments yet. Leave a comment! 💬',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            );
                          }

                          return ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: comments.length,
                            itemBuilder: (context, index) {
                              return _CommentTile(
                                photoId: photo.id,
                                comment: comments[index],
                              );
                            },
                          );
                        },
                      ),
                    ),

                    // Input
                    ChatInputBar(
                      hintText: 'Add a comment...',
                      onSend: (text) => _addComment(context, text),
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

  /// The photo's height at full width, capped at 55% of the screen so the
  /// chat keeps the rest. Re-evaluated as the keyboard opens and shrinks the
  /// space, so the photo gives way to typing rather than the chat.
  double _photoHeight(BoxConstraints constraints) {
    final maxHeight = constraints.maxHeight * 0.55;
    final natural = constraints.maxWidth / _safeAspect(photo.aspectRatio);
    // A panorama would otherwise be a thin strip; give it a usable band.
    final minHeight = maxHeight < 200 ? maxHeight : 200.0;
    return natural.clamp(minHeight, maxHeight);
  }
}

/// Width / height. Photos stored before aspect ratios were recorded, or with
/// a bad value, fall back to square; BoxFit.contain keeps them uncropped.
double _safeAspect(double ratio) => ratio.isFinite && ratio > 0 ? ratio : 1.0;

/// Splits the web modal between photo and chat.
///
/// The photo panel takes the width the photo needs at full height, and the
/// chat flexes between 340 and 460 around it, so the photo is shown whole
/// without wide side bars; the modal shrinks to fit rather than padding a
/// portrait with black. In a narrow window (this layout starts at 600px) the
/// bounds give way, the chat never taking more than half, so the two panels
/// always fit in [maxWidth].
@visibleForTesting
({double photoWidth, double chatWidth}) webModalSplit({
  required double maxWidth,
  required double height,
  required double aspectRatio,
}) {
  const chatMin = 340.0, chatMax = 460.0;
  // Under the photo: the user bar and the map button.
  const photoFooterHeight = 110.0;
  // Below this the user bar's name, heart and menu start to crowd.
  const photoMinWidth = 320.0;

  final room = maxWidth - 1; // the divider
  final photoNeeds = (height - photoFooterHeight) * _safeAspect(aspectRatio);
  final chatWidth = math.min(
    (room - photoNeeds).clamp(chatMin, chatMax),
    room / 2,
  );
  final photoRoom = room - chatWidth;
  final photoWidth = photoNeeds
      .clamp(math.min(photoMinWidth, photoRoom), photoRoom)
      .toDouble();
  return (photoWidth: photoWidth, chatWidth: chatWidth);
}

// ── Web: Modal with photo left, comments right ────────

class _WebPictureModal extends StatelessWidget {
  final PhotoPost photo;
  final VoidCallback? onClose;

  const _WebPictureModal({required this.photo, this.onClose});

  void _addComment(BuildContext context, String text) async {
    final currentUser = auth.FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      // A comment signed by a placeholder account would not belong to anyone,
      // so it could never be edited, deleted, or counted on a profile.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to add a comment.')),
      );
      return;
    }
    final userProfile = UserProfile.fromFirebaseUser(currentUser);
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Size the modal to the available window space (minus margin)
            // so it never gets clipped/overlapped when the browser is resized.
            final maxWidth = (constraints.maxWidth * 0.85).clamp(360.0, 1400.0);
            final height = (constraints.maxHeight * 0.85).clamp(360.0, 820.0);

            final (:photoWidth, :chatWidth) = webModalSplit(
              maxWidth: maxWidth,
              height: height,
              aspectRatio: photo.aspectRatio,
            );
            final width = photoWidth + 1 + chatWidth; // 1: the divider
            return Container(
              width: width,
              height: height,
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
                  SizedBox(
                    width: photoWidth,
                    child: Column(
                      children: [
                        Expanded(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Container(
                                color: Colors.black,
                                child: Image.network(
                                  photo.imageUrl,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: AppColors.surfaceVariant,
                                    child: const Icon(
                                      Icons.landscape,
                                      size: 64,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 12,
                                left: 12,
                                child: LocationPill(
                                  locationName:
                                      '${photo.location.name} · ${photo.location.region ?? ''}',
                                ),
                              ),
                            ],
                          ),
                        ),
                        // User info bar
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
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
                                    Text(
                                      photo.user.name,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      '${photo.user.role ?? "Contributor"} · Bay Area',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  if (photo.id.isNotEmpty) {
                                    firestoreService.incrementHeartCount(
                                      photo.id,
                                    );
                                  }
                                },
                                child: HeartCount(count: photo.heartCount),
                              ),
                              const SizedBox(width: 12),
                              // Only the owner or a moderator; firestore.rules refuse anyone else.
                              if (canModify(photo.user.id))
                                PopupMenuButton<String>(
                                  icon: const Icon(
                                    Icons.more_vert,
                                    size: 20,
                                    color: AppColors.textSecondary,
                                  ),
                                  onSelected: (val) async {
                                    if (val == 'edit') {
                                      EditPhotoDialog.show(context, photo);
                                    } else if (val == 'delete') {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text('Delete Photo?'),
                                          content: const Text(
                                            'Are you sure you want to delete this photo post?',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, false),
                                              child: const Text('Cancel'),
                                            ),
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, true),
                                              style: TextButton.styleFrom(
                                                foregroundColor: Colors.red,
                                              ),
                                              child: const Text('Delete'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirm == true) {
                                        // Image file and comments go with it.
                                        await PhotoDeletionService().deleteOne(
                                          photoId: photo.id,
                                          imageUrl: photo.imageUrl,
                                        );
                                        if (context.mounted) {
                                          (onClose ??
                                              () => Navigator.pop(context))();
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
                                          Icon(
                                            Icons.delete,
                                            size: 18,
                                            color: Colors.red,
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            'Delete Photo',
                                            style: TextStyle(color: Colors.red),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                        // The map button sits on its own row under the photo rather than
                        // as an icon in the crowded user bar, where it was easy to miss.
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                          child: SizedBox(
                            width: double.infinity,
                            child: MapLocationButton(
                              photo: photo,
                              prominent: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const VerticalDivider(width: 1),

                  // Right: Comments
                  SizedBox(
                    width: chatWidth,
                    child: Column(
                      children: [
                        // Close button
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
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
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }

                              final comments = snapshot.data ?? [];
                              if (comments.isEmpty) {
                                return const Center(
                                  child: Text(
                                    'No comments yet. Leave a comment! 💬',
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                );
                              }

                              return ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                itemCount: comments.length,
                                itemBuilder: (context, index) {
                                  return _CommentTile(
                                    photoId: photo.id,
                                    comment: comments[index],
                                  );
                                },
                              );
                            },
                          ),
                        ),

                        // Input
                        ChatInputBar(
                          hintText: 'Add a comment...',
                          onSend: (text) => _addComment(context, text),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
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
                await FirestoreService().updateComment(
                  photoId,
                  comment.id,
                  newText,
                );
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
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (comment.id.isNotEmpty && canModify(comment.user.id))
                      PopupMenuButton<String>(
                        icon: const Icon(
                          Icons.more_horiz,
                          size: 16,
                          color: AppColors.textSecondary,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onSelected: (val) async {
                          if (val == 'edit') {
                            _showEditCommentDialog(context);
                          } else if (val == 'delete') {
                            await FirestoreService().deleteComment(
                              photoId,
                              comment.id,
                            );
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
                                Text(
                                  'Delete Comment',
                                  style: TextStyle(color: Colors.red),
                                ),
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
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      comment.timestamp,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
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
