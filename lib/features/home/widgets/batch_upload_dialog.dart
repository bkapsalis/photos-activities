import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import '../../../core/data/mock_data.dart';
import '../../../core/models/models.dart';
import '../../../core/services/firestore_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/theme/app_colors.dart';

/// Represents a selected image with byte data in memory
class _SelectedImage {
  final String name;
  final Uint8List bytes;

  const _SelectedImage({required this.name, required this.bytes});
}

class BatchUploadDialog extends StatefulWidget {
  final String initialCategory;

  const BatchUploadDialog({super.key, this.initialCategory = 'Hiking'});

  static Future<void> show(BuildContext context, {String initialCategory = 'Hiking'}) {
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

  @override
  void initState() {
    super.initState();
    _selectedCategory = categories.contains(widget.initialCategory)
        ? widget.initialCategory
        : categories.first;

    // Default spot name
    _locationNameController.text = 'Bay Area Spot';
  }

  @override
  void dispose() {
    _locationNameController.dispose();
    _regionController.dispose();
    super.dispose();
  }

  Future<void> _pickMultipleImages() async {
    if (_isPicking) return;

    setState(() {
      _isPicking = true;
      _errorMessage = null;
    });

    try {
      final remaining = _maxImages - _selectedImages.length;
      if (remaining <= 0) {
        setState(() {
          _errorMessage = 'Maximum limit of $_maxImages images reached.';
          _isPicking = false;
        });
        return;
      }

      final images = await _storageService.pickMultiImage(limit: remaining);
      if (images.isEmpty) {
        setState(() => _isPicking = false);
        return;
      }

      final newImages = <_SelectedImage>[];
      for (final xFile in images) {
        if (_selectedImages.length + newImages.length >= _maxImages) break;

        Uint8List? bytes;
        try {
          bytes = await xFile.readAsBytes();
        } catch (_) {
          final file = File(xFile.path);
          if (await file.exists()) {
            bytes = await file.readAsBytes();
          }
        }

        if (bytes != null && bytes.isNotEmpty) {
          newImages.add(_SelectedImage(name: xFile.name, bytes: bytes));
        }
      }

      setState(() {
        _selectedImages.addAll(newImages);
        _isPicking = false;
        if (_selectedImages.isEmpty) {
          _errorMessage = 'Could not read image files. Please select JPEG or PNG images.';
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to pick images: $e';
        _isPicking = false;
      });
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
      // If no images picked yet, trigger picker
      await _pickMultipleImages();
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isUploading = true;
      _uploadedCount = 0;
      _failedCount = 0;
      _errorMessage = null;
    });

    final currentUser = auth.FirebaseAuth.instance.currentUser;
    final userProfile = currentUser != null
        ? UserProfile.fromFirebaseUser(currentUser)
        : MockUsers.me;

    final spotName = _locationNameController.text.trim().isNotEmpty
        ? _locationNameController.text.trim()
        : 'Bay Area Spot';
    final region = _regionController.text.trim().isNotEmpty
        ? _regionController.text.trim()
        : 'Bay Area, CA';

    for (int i = 0; i < _selectedImages.length; i++) {
      if (!mounted) return;

      final img = _selectedImages[i];
      final photoId = '${DateTime.now().millisecondsSinceEpoch}_$i';

      try {
        final imageUrl = await _storageService.uploadBytes(
          bytes: img.bytes,
          category: _selectedCategory,
          photoId: photoId,
        );

        if (imageUrl == null) {
          setState(() => _failedCount++);
          continue;
        }

        final location = Location(
          id: 'loc_$photoId',
          name: spotName,
          region: region,
          postCount: 1,
          category: _selectedCategory,
        );

        final photoPost = PhotoPost(
          id: photoId,
          imageUrl: imageUrl,
          location: location,
          user: userProfile,
          heartCount: 1,
          commentCount: 0,
          aspectRatio: 1.2,
          category: _selectedCategory.toLowerCase(),
          createdAt: DateTime.now(),
        );

        await _firestoreService.addPhoto(photoPost);
        setState(() => _uploadedCount++);
      } catch (e) {
        setState(() => _failedCount++);
      }
    }

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _failedCount == 0
                ? 'All $_uploadedCount photos published to Bay Area feed! 🎉'
                : '$_uploadedCount photos published, $_failedCount failed.',
          ),
          backgroundColor: _failedCount == 0 ? AppColors.primary : Colors.orange,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final progress = _selectedImages.isNotEmpty
        ? _uploadedCount / _selectedImages.length
        : 0.0;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: screenSize.height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        'Batch Upload Photos 📂',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _isUploading ? null : () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                Text(
                  'Select up to $_maxImages photos to upload at once',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 10),

                // 2. Scrollable Middle Body
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Buttons & Counter Row
                        Row(
                          children: [
                            ElevatedButton.icon(
                              onPressed: (_isUploading || _isPicking) ? null : _pickMultipleImages,
                              icon: _isPicking
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.photo_library, size: 18),
                              label: Text(
                                _selectedImages.isEmpty ? 'Choose Photos' : 'Add More Photos',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: _selectedImages.length >= _maxImages
                                    ? Colors.orange.withValues(alpha: 0.15)
                                    : AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${_selectedImages.length} / $_maxImages',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: _selectedImages.length >= _maxImages
                                      ? Colors.orange
                                      : AppColors.primary,
                                ),
                              ),
                            ),
                            const Spacer(),
                            if (_selectedImages.isNotEmpty && !_isUploading)
                              TextButton(
                                onPressed: _clearAll,
                                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                                child: const Text('Clear All',
                                    style: TextStyle(color: Colors.red, fontSize: 12)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Thumbnail Box (Height 140, scrollable GridView inside)
                        Container(
                          height: 140,
                          width: double.infinity,
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: _selectedImages.isEmpty
                              ? InkWell(
                                  onTap: (_isUploading || _isPicking) ? null : _pickMultipleImages,
                                  borderRadius: BorderRadius.circular(10),
                                  child: const Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.add_photo_alternate_outlined,
                                          size: 38, color: AppColors.primary),
                                      SizedBox(height: 6),
                                      Text(
                                        'Tap here to choose up to 50 photos',
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.bold),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        'Supports JPEG and PNG images',
                                        style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                      ),
                                    ],
                                  ),
                                )
                              : GridView.builder(
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 4,
                                    crossAxisSpacing: 6,
                                    mainAxisSpacing: 6,
                                  ),
                                  itemCount: _selectedImages.length,
                                  itemBuilder: (context, index) {
                                    final img = _selectedImages[index];
                                    return Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(6),
                                          child: Image.memory(
                                            img.bytes,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => Container(
                                              color: Colors.grey.shade300,
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  const Icon(Icons.image, size: 20, color: Colors.grey),
                                                  Text('#${index + 1}', style: const TextStyle(fontSize: 9)),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (_isUploading && index < _uploadedCount + _failedCount)
                                          Positioned.fill(
                                            child: Container(
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(6),
                                                color: index < _uploadedCount
                                                    ? Colors.green.withValues(alpha: 0.6)
                                                    : Colors.red.withValues(alpha: 0.6),
                                              ),
                                              child: Icon(
                                                index < _uploadedCount
                                                    ? Icons.check_circle
                                                    : Icons.error,
                                                color: Colors.white,
                                                size: 24,
                                              ),
                                            ),
                                          ),
                                        if (_isUploading && index == _uploadedCount + _failedCount)
                                          Positioned.fill(
                                            child: Container(
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(6),
                                                color: Colors.black.withValues(alpha: 0.5),
                                              ),
                                              child: const Center(
                                                child: SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child: CircularProgressIndicator(
                                                      color: Colors.white, strokeWidth: 2),
                                                ),
                                              ),
                                            ),
                                          ),
                                        if (!_isUploading)
                                          Positioned(
                                            top: 2,
                                            right: 2,
                                            child: GestureDetector(
                                              onTap: () => _removeImage(index),
                                              child: Container(
                                                padding: const EdgeInsets.all(2),
                                                decoration: const BoxDecoration(
                                                  color: Colors.black54,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(Icons.close,
                                                    size: 12, color: Colors.white),
                                              ),
                                            ),
                                          ),
                                        Positioned(
                                          bottom: 2,
                                          left: 3,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: Colors.black54,
                                              borderRadius: BorderRadius.circular(3),
                                            ),
                                            child: Text(
                                              '${index + 1}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                        ),
                        const SizedBox(height: 10),

                        // Category Dropdown
                        DropdownButtonFormField<String>(
                          initialValue: _selectedCategory,
                          decoration: const InputDecoration(
                            labelText: 'Category (applies to all photos)',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          ),
                          items: categories
                              .map((cat) => DropdownMenuItem(value: cat, child: Text(cat)))
                              .toList(),
                          onChanged: _isUploading
                              ? null
                              : (val) {
                                  if (val != null) setState(() => _selectedCategory = val);
                                },
                        ),
                        const SizedBox(height: 10),

                        // Spot Name Input
                        TextFormField(
                          controller: _locationNameController,
                          enabled: !_isUploading,
                          decoration: const InputDecoration(
                            labelText: 'Spot Name',
                            hintText: 'e.g. Marin Headlands',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          ),
                          validator: (val) =>
                              (val == null || val.trim().isEmpty) ? 'Please enter spot name' : null,
                        ),
                        const SizedBox(height: 10),

                        // Region Input
                        TextFormField(
                          controller: _regionController,
                          enabled: !_isUploading,
                          decoration: const InputDecoration(
                            labelText: 'Region / City (Optional)',
                            hintText: 'e.g. Marin County, CA',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          ),
                        ),
                        const SizedBox(height: 10),

                        if (_errorMessage != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(color: Colors.red, fontSize: 12),
                            ),
                          ),

                        // Progress bar during upload
                        if (_isUploading) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 8,
                              backgroundColor: AppColors.surfaceVariant,
                              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Uploading $_uploadedCount of ${_selectedImages.length} photos...'
                            '${_failedCount > 0 ? ' ($_failedCount failed)' : ''}',
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // 3. Pinned Big Action Button at bottom
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _isUploading
                        ? null
                        : (_selectedImages.isEmpty ? _pickMultipleImages : _uploadAll),
                    icon: _isUploading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : Icon(_selectedImages.isEmpty ? Icons.photo_library : Icons.cloud_upload),
                    label: Text(
                      _isUploading
                          ? 'Uploading Photos...'
                          : (_selectedImages.isEmpty
                              ? '📷 CHOOSE PHOTOS TO START UPLOAD'
                              : '🚀 START UPLOAD (${_selectedImages.length} PHOTO${_selectedImages.length == 1 ? '' : 'S'})'),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
