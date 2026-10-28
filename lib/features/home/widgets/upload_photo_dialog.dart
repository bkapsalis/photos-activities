import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:image_picker/image_picker.dart';
import '../../../core/data/mock_data.dart';
import '../../../core/models/models.dart';
import '../../../core/services/capture_location_service.dart';
import '../../../core/services/crash_reporting.dart';
import '../../../core/services/firestore_service.dart';
import '../../../core/services/image_processing_service.dart';
import '../../../core/services/performance_service.dart';
import '../../../core/services/photo_metadata_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/shared_widgets.dart';

class UploadPhotoDialog extends StatefulWidget {
  final String initialCategory;
  final ImageSource imageSource;

  const UploadPhotoDialog({
    super.key,
    this.initialCategory = 'Hiking Areas',
    this.imageSource = ImageSource.gallery,
  });

  /// Show dialog for camera capture
  static Future<void> showCamera(
    BuildContext context, {
    String initialCategory = 'Hiking Areas',
  }) {
    return showDialog(
      context: context,
      builder: (_) => UploadPhotoDialog(
        initialCategory: initialCategory,
        imageSource: ImageSource.camera,
      ),
    );
  }

  @override
  State<UploadPhotoDialog> createState() => _UploadPhotoDialogState();
}

class _UploadPhotoDialogState extends State<UploadPhotoDialog> {
  final _formKey = GlobalKey<FormState>();
  final _locationNameController = TextEditingController();
  final _regionController = TextEditingController();

  late String _selectedCategory;
  Uint8List? _imageBytes;
  bool _isUploading = false;
  String? _errorMessage;

  final StorageService _storageService = StorageService();
  final FirestoreService _firestoreService = FirestoreService();
  static const _metadataService = PhotoMetadataService();
  static const _imageProcessing = ImageProcessingService();

  /// Read from the original bytes at pick time, before any re-encode.
  PhotoMetadata _metadata = PhotoMetadata.empty;

  /// The phone's position being looked up for an in-app capture whose
  /// camera recorded no location. Publishing waits for it.
  Future<void>? _locationLookup;

  /// Bumped on every pick, so a lookup for a photo since replaced is dropped.
  int _pickGeneration = 0;

  @override
  void initState() {
    super.initState();
    _selectedCategory = categories.contains(widget.initialCategory)
        ? widget.initialCategory
        : categories.first;
    // Auto-open picker on launch
    WidgetsBinding.instance.addPostFrameCallback((_) => _pickImage());
  }

  @override
  void dispose() {
    _locationNameController.dispose();
    _regionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      // Asked before the camera opens, so the permission prompt does not
      // land on top of it. False on the web and when location is refused.
      final isCamera = widget.imageSource == ImageSource.camera;
      final canLocate = isCamera && await CaptureLocationService.prepare();

      // Routed per platform so the photo's location survives the pick; see
      // StorageService.pickSingleImage for what each platform does to EXIF.
      final picked = await _storageService.pickSingleImage(
        source: widget.imageSource,
      );
      if (picked != null) {
        final bytes = picked.bytes;

        if (bytes.isNotEmpty) {
          // Must happen here, on the untouched file. The upload re-encodes,
          // and a re-encoded JPEG carries none of this.
          final metadata = await _metadataService.extract(bytes);
          if (!mounted) return;
          final generation = ++_pickGeneration;
          setState(() {
            _imageBytes = bytes;
            _metadata = metadata;
            _errorMessage = null;
            // Looked up once the camera has closed: Android gives no position
            // to an app that is behind another one, and the phone is still
            // where the photo was just taken.
            _locationLookup = canLocate && !metadata.hasLocation
                ? _addDeviceLocation(generation)
                : null;
          });
        } else {
          throw Exception('Could not read image data from device');
        }
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'Failed to pick image: $e');
    }
  }

  /// Gives an in-app capture the phone's position, since the camera left
  /// its own out; see CaptureLocationService.
  Future<void> _addDeviceLocation(int generation) async {
    final position = await CaptureLocationService.current();
    if (!mounted || generation != _pickGeneration) return;
    debugPrint(
      position == null
          ? '[location] no device position either; photo will not map'
          : '[location] using device position (camera recorded none)',
    );
    setState(() {
      if (position != null) {
        _metadata = _metadata.withDeviceLocation(
          position.latitude,
          position.longitude,
        );
      }
      _locationLookup = null;
    });
  }

  Future<void> _uploadAndPublish() async {
    if (_imageBytes == null) {
      setState(() => _errorMessage = 'Please select a photo first');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isUploading = true;
      _errorMessage = null;
    });

    try {
      // A capture's location may still be arriving. It is bounded by its own
      // fix timeout; this is only a backstop.
      await _locationLookup?.timeout(
        const Duration(seconds: 20),
        onTimeout: () {},
      );

      final photoId = DateTime.now().millisecondsSinceEpoch.toString();

      // Needed before processing: the photographer's name is stamped on.
      final currentUser = auth.FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        // Never attribute an upload to a placeholder account: a photo whose
        // owner is fake cannot be edited, deleted or counted by whoever
        // actually took it.
        throw Exception('You must be signed in to upload a photo.');
      }
      final userProfile = UserProfile.fromFirebaseUser(currentUser);

      // Measure the original, then upload a resized copy with no metadata on
      // it. Only the Firestore document records where the photo was taken.
      final aspectRatio = await _storageService.getImageAspectRatio(
        _imageBytes!,
      );

      // Everything the user actually waits on the spinner for: resizing,
      // the Storage upload and the Firestore write. One number to watch for
      // "does publishing feel slow".
      await PerformanceService.trace('photo_upload_total', () async {
        final upload = await _imageProcessing.prepareForUpload(
          _imageBytes!,
          photographer: userProfile.name,
        );

        final imageUrl = await _storageService.uploadBytes(
          bytes: upload,
          category: _selectedCategory,
          photoId: photoId,
        );

        if (imageUrl == null) {
          throw Exception('Failed to upload image to Firebase Storage');
        }

        final decoded = await decodeImageFromList(_imageBytes!);
        final metadata = _metadata.withFallbackSize(
          decoded.width,
          decoded.height,
        );
        decoded.dispose();

        final location = Location(
          id: 'loc_$photoId',
          name: _locationNameController.text.trim(),
          region: _regionController.text.trim().isNotEmpty
              ? _regionController.text.trim()
              : 'Bay Area, CA',
          postCount: 1,
          category: _selectedCategory,
          // Mirrored onto the flat fields the map and directions already read,
          // so a photo with GPS is plotted the moment it is uploaded.
          latitude: metadata.latitude,
          longitude: metadata.longitude,
        );

        final photoPost = PhotoPost(
          id: photoId,
          imageUrl: imageUrl,
          location: location,
          user: userProfile,
          heartCount: 0,
          commentCount: 0,
          aspectRatio: aspectRatio,
          category: _selectedCategory,
          createdAt: DateTime.now(),
          metadata: metadata,
        );

        try {
          return await _firestoreService.addPhoto(photoPost);
        } catch (_) {
          // Without its document nothing points at the file; remove it
          // rather than leave it stranded in Storage.
          await _storageService.deleteUploadedFile(imageUrl);
          rethrow;
        }
      });

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Photo uploaded to $_selectedCategory! 🎉'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e, stack) {
      CrashReporting.recordError(e, stack, reason: 'photo upload failed');
      if (mounted) {
        setState(() {
          _isUploading = false;
          _errorMessage = 'Your photo was not uploaded. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCamera = widget.imageSource == ImageSource.camera;
    final title = isCamera ? 'Take a Photo 📷' : 'Upload from Device 🖼️';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      // Material's default 40-point side margins leave too little room on a
      // phone with a large display size; see dialogInsetPadding.
      insetPadding: dialogInsetPadding,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _isUploading
                          ? null
                          : () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Photo preview & re-pick
                GestureDetector(
                  onTap: _isUploading ? null : _pickImage,
                  child: Container(
                    height: 200,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: _imageBytes != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              _imageBytes!,
                              fit: BoxFit.cover,
                            ),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isCamera
                                    ? Icons.camera_alt
                                    : Icons.photo_library,
                                size: 40,
                                color: AppColors.textSecondary,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                isCamera
                                    ? 'Tap to open camera'
                                    : 'Tap to choose a photo',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                if (_imageBytes != null)
                  PhotoLocationStatus(
                    metadata: _metadata,
                    finding: _locationLookup != null,
                  ),
                const SizedBox(height: 16),

                // Category selector
                DropdownButtonFormField<String>(
                  initialValue: _selectedCategory,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  items: categories
                      .map(
                        (cat) => DropdownMenuItem(
                          value: cat,
                          child: Text(cat, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedCategory = val);
                  },
                ),
                const SizedBox(height: 16),

                // Location name (subcategory within the selected category)
                LocationNameField(
                  category: _selectedCategory,
                  controller: _locationNameController,
                  firestoreService: _firestoreService,
                ),
                const SizedBox(height: 16),

                // Region / City
                TextFormField(
                  controller: _regionController,
                  inputFormatters: placeNameLimit,
                  decoration: const InputDecoration(
                    labelText: 'Region / City (Optional)',
                    hintText: 'e.g. Los Gatos, CA',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _isUploading ? null : _uploadAndPublish,
                    icon: _isUploading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.cloud_upload),
                    label: Text(
                      _isUploading ? 'Uploading...' : 'Upload Photo',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One line under the preview saying whether the photo will appear on the
/// map, and where its location came from.
class PhotoLocationStatus extends StatelessWidget {
  final PhotoMetadata metadata;

  /// The phone's position is still being looked up.
  final bool finding;

  const PhotoLocationStatus({
    super.key,
    required this.metadata,
    required this.finding,
  });

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String text, Color color) = switch (metadata) {
      _ when finding => (
        Icons.my_location,
        'Finding your location…',
        AppColors.textSecondary,
      ),
      PhotoMetadata(hasLocation: false) => (
        Icons.location_off,
        'No location — this photo won\'t appear on the map',
        AppColors.textSecondary,
      ),
      PhotoMetadata(locationSource: LocationSource.device) => (
        Icons.my_location,
        'Location: where you are now',
        AppColors.primaryDark,
      ),
      _ => (
        Icons.location_on,
        'Location from the photo',
        AppColors.primaryDark,
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12, color: color)),
          ),
        ],
      ),
    );
  }
}
