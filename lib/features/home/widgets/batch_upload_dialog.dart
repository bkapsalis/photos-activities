import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import '../../../core/data/mock_data.dart';
import '../../../core/models/models.dart';
import '../../../core/services/firestore_service.dart';
import '../../../core/services/image_processing_service.dart';
import '../../../core/services/performance_service.dart';
import '../../../core/services/photo_metadata_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/shared_widgets.dart';

class BatchUploadDialog extends StatefulWidget {
  final String initialCategory;

  const BatchUploadDialog({super.key, this.initialCategory = 'Hiking Areas'});

  static Future<void> show(
    BuildContext context, {
    String initialCategory = 'Hiking Areas',
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => BatchUploadDialog(initialCategory: initialCategory),
    );
  }

  @override
  State<BatchUploadDialog> createState() => _BatchUploadDialogState();
}

class _BatchUploadDialogState extends State<BatchUploadDialog> {
  static const int _maxImages = 50;

  final _formKey = GlobalKey<FormState>();
  final _locationNameController = TextEditingController();
  final _regionController = TextEditingController();

  late String _selectedCategory;
  final List<_SelectedImage> _selectedImages = [];
  bool _isPicking = false;
  bool _isUploading = false;
  int _uploadedCount = 0;
  int _failedCount = 0;
  String? _errorMessage;

  final StorageService _storageService = StorageService();
  final FirestoreService _firestoreService = FirestoreService();
  static const _metadataService = PhotoMetadataService();
  static const _imageProcessing = ImageProcessingService();

  @override
  void initState() {
    super.initState();
    _selectedCategory = categories.contains(widget.initialCategory)
        ? widget.initialCategory
        : categories.first;
  }

  @override
  void dispose() {
    _locationNameController.dispose();
    _regionController.dispose();
    super.dispose();
  }

  Future<void> _selectFolder() async {
    if (_isPicking) return;
    setState(() {
      _isPicking = true;
      _errorMessage = null;
    });

    try {
      final remaining = _maxImages - _selectedImages.length;
      if (remaining <= 0) {
        setState(() {
          _errorMessage = 'Maximum $_maxImages images reached.';
          _isPicking = false;
        });
        return;
      }

      final picked = await _storageService.pickFolderAndScanImages(
        limit: remaining,
      );

      if (picked.isNotEmpty) {
        setState(() {
          for (final f in picked) {
            if (_selectedImages.length < _maxImages) {
              _selectedImages.add(_SelectedImage(name: f.name, bytes: f.bytes));
            }
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'Error: $e');
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  Future<void> _selectFiles() async {
    if (_isPicking) return;
    setState(() {
      _isPicking = true;
      _errorMessage = null;
    });

    try {
      final remaining = _maxImages - _selectedImages.length;
      if (remaining <= 0) {
        setState(() {
          _errorMessage = 'Maximum $_maxImages images reached.';
          _isPicking = false;
        });
        return;
      }

      final picked = await _storageService.pickFilesViaFilePicker(
        limit: remaining,
      );

      if (picked.isNotEmpty) {
        setState(() {
          for (final f in picked) {
            if (_selectedImages.length < _maxImages) {
              _selectedImages.add(_SelectedImage(name: f.name, bytes: f.bytes));
            }
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'Error: $e');
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  void _removeImage(int index) {
    setState(() => _selectedImages.removeAt(index));
  }

  void _clearAll() {
    setState(() => _selectedImages.clear());
  }

  Future<void> _uploadAll() async {
    if (_selectedImages.isEmpty) {
      setState(() => _errorMessage = 'Please select images first');
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

    for (int i = 0; i < _selectedImages.length; i++) {
      final img = _selectedImages[i];
      try {
        final photoId = '${DateTime.now().millisecondsSinceEpoch}_$i';

        // This route hands back untouched originals - it is the one path on
        // Android that keeps GPS - so the metadata is read here, before the
        // file is re-encoded for upload.
        final metadataFromFile = await _metadataService.extract(img.bytes);
        final aspectRatio = await _storageService.getImageAspectRatio(
          img.bytes,
        );
        final decoded = await decodeImageFromList(img.bytes);
        final metadata = metadataFromFile.withFallbackSize(
          decoded.width,
          decoded.height,
        );
        decoded.dispose();

        // Same trace name as the single-upload dialog: both feed one
        // "how long does publishing take" distribution in the dashboard.
        await PerformanceService.trace('photo_upload_total', () async {
          final upload = await _imageProcessing.prepareForUpload(
            img.bytes,
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

          await _firestoreService.addPhoto(photoPost);
        });
        if (mounted) setState(() => _uploadedCount++);
      } catch (e) {
        if (mounted) setState(() => _failedCount++);
      }
    }

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _failedCount == 0
                ? 'All $_uploadedCount photos uploaded! 🎉'
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
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
        child: Padding(
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
                    const Expanded(
                      child: Text(
                        'Upload from Folder 📁',
                        style: TextStyle(
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
                const SizedBox(height: 12),

                // Two action buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isPicking || _isUploading
                            ? null
                            : _selectFolder,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Select Folder'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isPicking || _isUploading
                            ? null
                            : _selectFiles,
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Select Files'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Selected images count & clear
                if (_selectedImages.isNotEmpty)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          '${_selectedImages.length} image${_selectedImages.length == 1 ? '' : 's'} selected',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      TextButton(
                        onPressed: _isUploading ? null : _clearAll,
                        child: const Text('Clear All'),
                      ),
                    ],
                  ),

                // Image thumbnails
                if (_selectedImages.isNotEmpty)
                  SizedBox(
                    height: 80,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _selectedImages.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(
                                  _selectedImages[index].bytes,
                                  width: 70,
                                  height: 70,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              if (!_isUploading)
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: GestureDetector(
                                    onTap: () => _removeImage(index),
                                    child: Container(
                                      width: 20,
                                      height: 20,
                                      decoration: const BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        size: 12,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 12),

                // Category
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
                  onChanged: (val) {
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

                // Region
                TextFormField(
                  controller: _regionController,
                  decoration: const InputDecoration(
                    labelText: 'Region / City (Optional)',
                    hintText: 'e.g. Los Gatos, CA',
                    border: OutlineInputBorder(),
                    isDense: true,
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

                // Upload progress
                if (_isUploading)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      children: [
                        LinearProgressIndicator(
                          value: _selectedImages.isNotEmpty
                              ? (_uploadedCount + _failedCount) /
                                    _selectedImages.length
                              : 0,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$_uploadedCount / ${_selectedImages.length} uploaded',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),

                // Upload button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _isUploading || _selectedImages.isEmpty
                        ? null
                        : _uploadAll,
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
                          : 'Upload ${_selectedImages.length} Photo${_selectedImages.length == 1 ? '' : 's'}',
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

class _SelectedImage {
  final String name;
  final Uint8List bytes;
  const _SelectedImage({required this.name, required this.bytes});
}
