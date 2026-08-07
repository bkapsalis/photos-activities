import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:image_picker/image_picker.dart';
import '../../../core/data/mock_data.dart';
import '../../../core/models/models.dart';
import '../../../core/services/firestore_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/theme/app_colors.dart';

class UploadPhotoDialog extends StatefulWidget {
  final String initialCategory;

  const UploadPhotoDialog({super.key, this.initialCategory = 'Hiking'});

  static Future<void> show(BuildContext context, {String initialCategory = 'Hiking'}) {
    return showDialog(
      context: context,
      builder: (_) => UploadPhotoDialog(initialCategory: initialCategory),
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
  String? _sampleImageUrl;
  bool _isUploading = false;
  String? _errorMessage;

  final StorageService _storageService = StorageService();
  final FirestoreService _firestoreService = FirestoreService();

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

  Future<void> _pickImage(ImageSource source) async {
    try {
      final image = await _storageService.pickImage(source: source);
      if (image != null) {
        Uint8List? bytes;
        try {
          bytes = await image.readAsBytes();
        } catch (_) {
          final file = File(image.path);
          if (await file.exists()) {
            bytes = await file.readAsBytes();
          }
        }

        if (bytes != null && bytes.isNotEmpty) {
          setState(() {
            _imageBytes = bytes;
            _sampleImageUrl = null;
            _errorMessage = null;
          });
        } else {
          throw Exception('Could not read image data from device');
        }
      }
    } catch (e) {
      setState(() => _errorMessage = 'Failed to pick image: $e');
    }
  }

  void _usePresetPhoto() {
    final sampleSeeds = ['bayarea', 'marinhills', 'goldengate', 'redwoods', 'tilden'];
    final seed = sampleSeeds[DateTime.now().second % sampleSeeds.length];
    final url = 'https://picsum.photos/seed/$seed/800/600';
    setState(() {
      _imageBytes = null;
      _sampleImageUrl = url;
      _errorMessage = null;
    });
  }

  Future<void> _uploadAndPublish() async {
    if (_imageBytes == null && _sampleImageUrl == null) {
      setState(() => _errorMessage = 'Please select a photo to share');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isUploading = true;
      _errorMessage = null;
    });

    try {
      final photoId = DateTime.now().millisecondsSinceEpoch.toString();
      String? imageUrl = _sampleImageUrl;

      if (_imageBytes != null) {
        imageUrl = await _storageService.uploadBytes(
          bytes: _imageBytes!,
          category: _selectedCategory,
          photoId: photoId,
        );
      }

      if (imageUrl == null) {
        throw Exception('Failed to upload image to Firebase Storage');
      }

      final currentUser = auth.FirebaseAuth.instance.currentUser;
      final userProfile = currentUser != null
          ? UserProfile.fromFirebaseUser(currentUser)
          : MockUsers.me;

      final location = Location(
        id: 'loc_$photoId',
        name: _locationNameController.text.trim(),
        region: _regionController.text.trim().isNotEmpty
            ? _regionController.text.trim()
            : 'Bay Area, CA',
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

      final docId = await _firestoreService.addPhoto(photoPost);

      if (docId != null && mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo published to Bay Area feed! 🎉'),
            backgroundColor: AppColors.primary,
          ),
        );
      } else {
        throw Exception('Failed to save photo metadata to Firestore');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Share a Bay Area Spot 📸',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _isUploading ? null : () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Photo preview & selection
                GestureDetector(
                  onTap: _isUploading
                      ? null
                      : () {
                          showModalBottomSheet(
                            context: context,
                            builder: (ctx) => SafeArea(
                              child: Wrap(
                                children: [
                                  ListTile(
                                    leading: const Icon(Icons.photo_library),
                                    title: const Text('Choose from Gallery'),
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      _pickImage(ImageSource.gallery);
                                    },
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.camera_alt),
                                    title: const Text('Take a Photo'),
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      _pickImage(ImageSource.camera);
                                    },
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.landscape),
                                    title: const Text('Use Preset Bay Area Photo (Emulator friendly)'),
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      _usePresetPhoto();
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                  child: Container(
                    height: 180,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: _imageBytes != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(_imageBytes!, fit: BoxFit.cover),
                          )
                        : _sampleImageUrl != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(_sampleImageUrl!, fit: BoxFit.cover),
                              )
                            : const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_a_photo, size: 40, color: AppColors.textSecondary),
                                  SizedBox(height: 8),
                                  Text('Tap to pick from gallery, camera, or preset',
                                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                ],
                              ),
                  ),
                ),
                const SizedBox(height: 16),

                // Category selector
                DropdownButtonFormField<String>(
                  initialValue: _selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  items: categories
                      .map((cat) => DropdownMenuItem(value: cat, child: Text(cat)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedCategory = val);
                  },
                ),
                const SizedBox(height: 16),

                // Location name
                TextFormField(
                  controller: _locationNameController,
                  decoration: const InputDecoration(
                    labelText: 'Spot Name',
                    hintText: 'e.g. Marin Headlands, Palace of Fine Arts',
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) =>
                      (val == null || val.trim().isEmpty) ? 'Please enter spot name' : null,
                ),
                const SizedBox(height: 16),

                // Region / City
                TextFormField(
                  controller: _regionController,
                  decoration: const InputDecoration(
                    labelText: 'Region / City (Optional)',
                    hintText: 'e.g. Marin County, CA',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_errorMessage!,
                        style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ),

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isUploading ? null : _uploadAndPublish,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _isUploading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('Publish Photo',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
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
