import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import '../../../core/data/mock_data.dart';
import '../../../core/models/models.dart';
import '../../../core/services/crash_reporting.dart';
import '../../../core/services/firestore_service.dart';
import '../../../core/services/image_processing_service.dart';
import '../../../core/services/performance_service.dart';
import '../../../core/services/photo_metadata_service.dart';
import '../../../core/services/photo_pickers.dart';
import '../../../core/services/picked_image.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/upload_sources.dart';
import '../../../core/widgets/shared_widgets.dart';

/// "Upload Image or Images": choose where the photos come from (this device
/// or the cloud), then which of them to upload, then where they were taken.
///
/// One photo or a folderful go through the same steps. Photos picked one by
/// one arrive ticked, since picking them was the choice; a folder's arrive
/// unticked, to be chosen from or taken whole with Select all.
class UploadImagesDialog extends StatefulWidget {
  final String initialCategory;

  const UploadImagesDialog({super.key, this.initialCategory = 'Hiking Areas'});

  static Future<void> show(
    BuildContext context, {
    String initialCategory = 'Hiking Areas',
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => UploadImagesDialog(initialCategory: initialCategory),
    );
  }

  @override
  State<UploadImagesDialog> createState() => _UploadImagesDialogState();
}

class _UploadImagesDialogState extends State<UploadImagesDialog> {
  /// Photos on the screen at once: a folder's newest, if it holds more.
  static const int _maxImages = 200;

  final _formKey = GlobalKey<FormState>();
  final _locationNameController = TextEditingController();
  final _regionController = TextEditingController();

  late String _selectedCategory;
  final List<PickedImage> _images = [];

  /// Back on the source list to add to photos already picked.
  bool _addingMore = false;
  bool _isPicking = false;
  bool _isUploading = false;
  int _uploadedCount = 0;
  int _failedCount = 0;
  String? _errorMessage;

  final StorageService _storageService = StorageService();
  final FirestoreService _firestoreService = FirestoreService();
  static const _metadataService = PhotoMetadataService();
  static const _imageProcessing = ImageProcessingService();

  bool get _choosingSource => _images.isEmpty || _addingMore;

  List<PickedImage> get _selected =>
      _images.where((image) => image.selected).toList();

  @override
  void initState() {
    super.initState();
    _selectedCategory = categories.contains(widget.initialCategory)
        ? widget.initialCategory
        : categories.first;
    preparePhotoPickers();
  }

  @override
  void dispose() {
    _locationNameController.dispose();
    _regionController.dispose();
    super.dispose();
  }

  Future<void> _pickFrom(UploadSource source) async {
    if (_isPicking) return;
    final remaining = _maxImages - _images.length;
    if (remaining <= 0) {
      setState(
        () => _errorMessage = 'You can add up to $_maxImages photos at a time.',
      );
      return;
    }
    setState(() {
      _isPicking = true;
      _errorMessage = null;
    });

    try {
      final picked = switch (source) {
        UploadSource.device => await pickDevicePhotos(limit: remaining),
        UploadSource.cloud => await pickCloudPhotos(limit: remaining),
      };
      if (!mounted || picked.isEmpty) return;
      setState(() {
        _images.addAll(picked.take(remaining));
        _addingMore = false;
      });
    } catch (e, stack) {
      CrashReporting.recordError(
        e,
        stack,
        reason: 'photos could not be picked',
      );
      if (mounted) {
        setState(
          () => _errorMessage =
              'Those photos could not be opened. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  void _setAll(bool selected) {
    setState(() {
      for (final image in _images) {
        image.selected = selected;
      }
    });
  }

  Future<void> _uploadSelected() async {
    final toUpload = _selected;
    if (toUpload.isEmpty) {
      setState(() => _errorMessage = 'Tap the photos to upload first.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isUploading = true;
      _errorMessage = null;
      _uploadedCount = 0;
      _failedCount = 0;
    });

    final currentUser = auth.FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      setState(() {
        _isUploading = false;
        _errorMessage = 'You must be signed in to upload photos.';
      });
      return;
    }
    final userProfile = UserProfile.fromFirebaseUser(currentUser);

    for (int i = 0; i < toUpload.length; i++) {
      final img = toUpload[i];
      try {
        final photoId = '${DateTime.now().millisecondsSinceEpoch}_$i';
        // Read now, one photo at a time: a folder's worth at once would not
        // fit in a phone's memory.
        final bytes = await img.read();

        // Every source here hands back untouched originals - on Android the
        // document picker is the one route that keeps GPS - so the metadata
        // is read here, before the file is re-encoded for upload.
        final metadataFromFile = await _metadataService.extract(bytes);
        final aspectRatio = await _storageService.getImageAspectRatio(bytes);
        final decoded = await decodeImageFromList(bytes);
        final metadata = metadataFromFile.withFallbackSize(
          decoded.width,
          decoded.height,
        );
        decoded.dispose();

        // Same trace name as the camera dialog: both feed one "how long
        // does publishing take" distribution in the dashboard.
        await PerformanceService.trace('photo_upload_total', () async {
          final upload = await _imageProcessing.prepareForUpload(
            bytes,
            photographer: userProfile.name,
          );
          final imageUrl = await _storageService.uploadBytes(
            bytes: upload,
            category: _selectedCategory,
            photoId: photoId,
          );

          if (imageUrl == null) throw Exception('Upload failed');

          final location = Location(
            id: 'loc_$photoId',
            name: _locationNameController.text.trim(),
            region: _regionController.text.trim().isNotEmpty
                ? _regionController.text.trim()
                : 'Bay Area, CA',
            postCount: 1,
            category: _selectedCategory,
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
            await _firestoreService.addPhoto(photoPost);
          } catch (_) {
            // Without its document nothing points at the file; remove it
            // rather than leave it stranded in Storage.
            await _storageService.deleteUploadedFile(imageUrl);
            rethrow;
          }
        });
        if (mounted) setState(() => _uploadedCount++);
      } catch (e, stack) {
        CrashReporting.recordError(e, stack, reason: 'batch upload failed');
        if (mounted) setState(() => _failedCount++);
      }
    }

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _failedCount == 0
                ? (_uploadedCount == 1
                      ? 'Photo uploaded! 🎉'
                      : 'All $_uploadedCount photos uploaded! 🎉')
                : '$_uploadedCount uploaded, $_failedCount failed.',
          ),
          backgroundColor: _failedCount == 0
              ? AppColors.primary
              : Colors.orange,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      // Material's default 40-point side margins leave too little room on a
      // phone with a large display size; see dialogInsetPadding.
      insetPadding: dialogInsetPadding,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(),
                const SizedBox(height: 12),
                if (_choosingSource) ...[
                  UploadSourceList(
                    sources: [
                      UploadSource.device,
                      if (cloudPhotosAvailable) UploadSource.cloud,
                    ],
                    enabled: !_isPicking,
                    onPick: _pickFrom,
                  ),
                  if (_isPicking)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: LinearProgressIndicator(),
                    ),
                  if (_errorMessage != null) _error(),
                ] else
                  ..._review(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        if (_addingMore && _images.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back to your photos',
            onPressed: _isPicking
                ? null
                : () => setState(() => _addingMore = false),
          ),
        const Expanded(
          child: Text(
            'Upload Image or Images',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: _isUploading ? null : () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _error() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        _errorMessage!,
        style: const TextStyle(color: Colors.red, fontSize: 12),
      ),
    );
  }

  List<Widget> _review() {
    final count = _selected.length;
    return [
      UploadSelectionGrid(
        images: _images,
        enabled: !_isUploading,
        onToggle: (image) => setState(() => image.selected = !image.selected),
        onSelectAll: () => _setAll(true),
        onSelectNone: () => _setAll(false),
      ),
      if (_images.length < _maxImages && !_isUploading)
        TextButton.icon(
          onPressed: () => setState(() {
            _addingMore = true;
            _errorMessage = null;
          }),
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: const Text('Add more photos'),
        ),
      const SizedBox(height: 12),

      DropdownButtonFormField<String>(
        initialValue: _selectedCategory,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Category',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        items: categories
            .map(
              (c) => DropdownMenuItem(
                value: c,
                child: Text(c, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: _isUploading
            ? null
            : (val) {
                if (val != null) setState(() => _selectedCategory = val);
              },
      ),
      const SizedBox(height: 12),

      // Location name (subcategory within the selected category)
      LocationNameField(
        category: _selectedCategory,
        controller: _locationNameController,
        firestoreService: _firestoreService,
        isDense: true,
      ),
      const SizedBox(height: 12),

      TextFormField(
        controller: _regionController,
        inputFormatters: placeNameLimit,
        decoration: const InputDecoration(
          labelText: 'Region / City (Optional)',
          hintText: 'e.g. Los Gatos, CA',
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      const SizedBox(height: 4),
      if (_errorMessage != null) _error(),
      const SizedBox(height: 12),

      if (_isUploading)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            children: [
              LinearProgressIndicator(
                value: count > 0 ? (_uploadedCount + _failedCount) / count : 0,
              ),
              const SizedBox(height: 4),
              Text(
                '$_uploadedCount / $count uploaded',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),

      SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton.icon(
          onPressed: _isUploading || count == 0 ? null : _uploadSelected,
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
            _isUploading
                ? 'Uploading...'
                : 'Upload $count Photo${count == 1 ? '' : 's'}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
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
    ];
  }
}

/// The places photos can be picked from, one tappable row each.
class UploadSourceList extends StatelessWidget {
  final List<UploadSource> sources;
  final bool enabled;
  final ValueChanged<UploadSource> onPick;

  const UploadSourceList({
    super.key,
    required this.sources,
    required this.onPick,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final source in sources)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _SourceTile(
              info: describeUploadSource(
                source,
                isWeb: kIsWeb,
                platform: defaultTargetPlatform,
              ),
              onTap: enabled ? () => onPick(source) : null,
            ),
          ),
      ],
    );
  }
}

class _SourceTile extends StatelessWidget {
  final ({String title, String subtitle, IconData icon}) info;
  final VoidCallback? onTap;

  const _SourceTile({required this.info, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: onTap != null,
      onTap: onTap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.divider),
      ),
      leading: Icon(info.icon, color: AppColors.primary),
      title: Text(
        info.title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(info.subtitle),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

/// The picked photos as a grid of ticks: tap one to include or leave it out,
/// or take them all, or none, at once.
class UploadSelectionGrid extends StatelessWidget {
  final List<PickedImage> images;
  final bool enabled;
  final ValueChanged<PickedImage> onToggle;
  final VoidCallback onSelectAll;
  final VoidCallback onSelectNone;

  const UploadSelectionGrid({
    super.key,
    required this.images,
    required this.onToggle,
    required this.onSelectAll,
    required this.onSelectNone,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final count = images.where((image) => image.selected).length;
    final all = count == images.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$count of ${images.length} selected',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: enabled && !all ? onSelectAll : null,
              child: const Text('Select all'),
            ),
            TextButton(
              onPressed: enabled && count > 0 ? onSelectNone : null,
              child: const Text('Select none'),
            ),
          ],
        ),
        if (count == 0)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Tap the photos to upload, or Select all.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
        ConstrainedBox(
          // As tall as the photos need, up to about two and a half rows, so
          // a long selection visibly scrolls.
          constraints: const BoxConstraints(maxHeight: 220),
          child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 96,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemCount: images.length,
            itemBuilder: (context, index) => _Thumbnail(
              image: images[index],
              onTap: enabled ? () => onToggle(images[index]) : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final PickedImage image;
  final VoidCallback? onTap;

  const _Thumbnail({required this.image, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final preview = image.preview;
    const placeholder = ColoredBox(
      color: AppColors.divider,
      child: Center(child: Icon(Icons.image_outlined)),
    );
    return Semantics(
      label: image.name,
      checked: image.selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: preview == null
                  ? placeholder
                  : Image(
                      image: preview,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => placeholder,
                    ),
            ),
            if (!image.selected)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white54,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            Positioned(
              top: 4,
              right: 4,
              child: Icon(
                image.selected ? Icons.check_circle : Icons.circle_outlined,
                color: image.selected ? AppColors.primary : Colors.white,
                shadows: const [Shadow(blurRadius: 3)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
