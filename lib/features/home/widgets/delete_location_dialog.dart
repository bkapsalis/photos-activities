import 'package:flutter/material.dart';

import '../../../core/services/photo_deletion_service.dart';
import '../../../core/theme/app_colors.dart';

/// Confirms, then performs, "delete every photo in this location".
///
/// This is the one irreversible bulk action in the app, so the dialog names
/// the location and the exact count rather than asking "are you sure?", and
/// the confirm button repeats the number. A reader who opened the wrong tab
/// sees the wrong name before they see a button worth pressing.
class DeleteLocationDialog {
  const DeleteLocationDialog._();

  static Future<void> show(
    BuildContext context, {
    required String category,
    required String locationName,
    required int photoCount,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final service = PhotoDeletionService();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete all of $locationName?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              photoCount == 1
                  ? 'This deletes the 1 photo in $locationName, along with its '
                        'comments and its image file.'
                  : 'This deletes all $photoCount photos in $locationName, '
                        'along with their comments and image files.',
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 12),
            Text(
              'Photos in other locations under $category are not touched.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            const Text(
              'This cannot be undone.',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.heartRed,
            ),
            child: Text(
              photoCount == 1 ? 'Delete 1 photo' : 'Delete $photoCount photos',
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    // Deleting a folder of photos means a file round-trip each, so the reader
    // gets a blocking spinner rather than a frozen-looking tab strip.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    BulkDeleteResult? result;
    Object? error;
    try {
      result = await service.deleteLocation(
        category: category,
        locationName: locationName,
      );
    } catch (e) {
      error = e;
    }

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // the spinner

    messenger.showSnackBar(
      SnackBar(
        content: Text(_message(locationName, result, error)),
        backgroundColor: (error != null || (result?.failed ?? 0) > 0)
            ? AppColors.heartRed
            : AppColors.primary,
      ),
    );
  }

  static String _message(
    String locationName,
    BulkDeleteResult? result,
    Object? error,
  ) {
    if (error != null) return 'Could not delete $locationName: $error';
    if (result == null || result.isEmpty) {
      return 'Nothing to delete in $locationName.';
    }
    final photos = result.photosDeleted == 1
        ? '1 photo'
        : '${result.photosDeleted} photos';
    if (result.failed > 0) {
      return 'Deleted $photos from $locationName, but ${result.failed} '
          'could not be removed.';
    }
    return 'Deleted $photos from $locationName.';
  }
}
