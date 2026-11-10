import 'package:flutter/material.dart';
import '../../../core/services/firestore_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/upload_sources.dart';
import '../../../core/widgets/live_data.dart';
import 'upload_images_dialog.dart';
import 'upload_photo_dialog.dart';

/// The two ways to upload, behind the phone's + button.
void showUploadOptions(BuildContext context, String category) {
  showModalBottomSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: Wrap(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Upload',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt, color: AppColors.primary),
            title: const Text('Take a Photo'),
            subtitle: const Text('Open camera and upload'),
            onTap: () {
              Navigator.pop(ctx);
              UploadPhotoDialog.showCamera(context, initialCategory: category);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library, color: AppColors.primary),
            title: const Text('Upload Image or Images'),
            subtitle: const Text(uploadSourcesSummary),
            onTap: () {
              Navigator.pop(ctx);
              UploadImagesDialog.show(context, initialCategory: category);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// A category's location chats, as a sheet: the phone's way in, and the
/// wide layout's when there is no room for its sidebar.
void showLocationChats(
  BuildContext context, {
  required String category,
  required FirestoreService firestoreService,
  Function(String locationName)? onChatTap,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.8,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.forum, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    '$category — Location Chats',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: LiveData<List<String>>(
                identity: category,
                stream: () =>
                    firestoreService.streamDistinctLocations(category),
                errorMessage: 'Locations could not be loaded.',
                builder: (context, locations) {
                  if (locations.isEmpty) {
                    return const Center(
                      child: Text(
                        'No locations yet. Upload photos to create location chats!',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    );
                  }
                  return ListView.builder(
                    controller: scrollController,
                    itemCount: locations.length,
                    itemBuilder: (context, index) {
                      final locName = locations[index];
                      return ListTile(
                        leading: const Icon(
                          Icons.chat_bubble_outline,
                          color: AppColors.primary,
                        ),
                        title: Text(locName),
                        subtitle: Text(
                          category,
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.pop(ctx);
                          onChatTap?.call(locName);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    ),
  );
}
