import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../core/services/ai_service.dart';
import '../../core/services/crash_reporting.dart';
import '../../core/theme/app_colors.dart';

/// A comment the AI posted: badged as AI, laid out as the animal's name and
/// description, and reminding readers it can be wrong. Nobody edits one; a
/// moderator may delete it.
class AiCommentTile extends StatelessWidget {
  final Comment comment;

  /// Null hides the menu, as for anyone who is not a moderator.
  final VoidCallback? onDelete;

  const AiCommentTile({super.key, required this.comment, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final animal = comment.animal;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: comment.user.avatarColor,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.pets, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        comment.user.name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const AiBadge(),
                    const Spacer(),
                    if (onDelete != null)
                      PopupMenuButton<String>(
                        icon: const Icon(
                          Icons.more_horiz,
                          size: 16,
                          color: AppColors.textSecondary,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onSelected: (_) => onDelete!(),
                        itemBuilder: (_) => [
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
                if (animal != null) ...[
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: animal.isUncertain
                              ? 'Possibly ${animal.commonName}'
                              : animal.commonName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (animal.scientificName.isNotEmpty)
                          TextSpan(
                            text: '  ${animal.scientificName}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    animal.description,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ] else
                  Text(
                    comment.text,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: AppColors.textPrimary,
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (comment.timestamp.isNotEmpty) comment.timestamp,
                    'AI-generated, may be wrong',
                  ].join(' · '),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The small "AI" label beside the AI's name.
class AiBadge extends StatelessWidget {
  const AiBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.ai.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'AI',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: AppColors.ai,
        ),
      ),
    );
  }
}

/// A moderator's "More info about the animals": the AI names each animal in
/// the photo and posts a comment about it. Shown to moderators only, since
/// each look costs money; everyone can read the comments.
class AnimalInfoButton extends StatefulWidget {
  final String photoId;

  const AnimalInfoButton({super.key, required this.photoId});

  @override
  State<AnimalInfoButton> createState() => _AnimalInfoButtonState();
}

class _AnimalInfoButtonState extends State<AnimalInfoButton> {
  bool _busy = false;

  Future<void> _describe() async {
    // Looked up before the await: the photo may be closed meanwhile.
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    String message;
    try {
      message = (await AiService().describeAnimals(widget.photoId)).message;
    } catch (error, stack) {
      CrashReporting.recordError(error, stack, reason: 'describing animals');
      message = aiErrorMessage(error);
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _busy ? null : _describe,
      icon: _busy
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.pets, size: 18),
      label: Text(_busy ? 'The AI is looking…' : 'More info about the animals'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primaryDark,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

/// What to tell the moderator when an AI request fails. The functions word
/// the errors they expect (a deleted photo, an image too large to send);
/// anything else gets a general line.
String aiErrorMessage(Object error) {
  const fallback = 'The AI could not look at this just now. Please try again.';
  if (error is! FirebaseFunctionsException) return fallback;
  final message = error.message ?? '';
  // A bare status such as "NOT_FOUND" comes from the platform, not from the
  // functions: most likely they are not deployed to this project.
  if (message.isEmpty || RegExp(r'^[A-Z_ ]+$').hasMatch(message)) {
    return fallback;
  }
  return switch (error.code) {
    'not-found' ||
    'failed-precondition' ||
    'permission-denied' ||
    'unavailable' => message,
    _ => fallback,
  };
}
