import 'package:flutter/material.dart';
import '../../../core/data/mock_data.dart';
import '../../../core/models/models.dart';
import '../../../core/services/firestore_service.dart';
import '../../../core/theme/app_colors.dart';

class EditPhotoDialog extends StatefulWidget {
  final PhotoPost photo;

  const EditPhotoDialog({super.key, required this.photo});

  static Future<void> show(BuildContext context, PhotoPost photo) {
    return showDialog(
      context: context,
      builder: (_) => EditPhotoDialog(photo: photo),
    );
  }

  @override
  State<EditPhotoDialog> createState() => _EditPhotoDialogState();
}

class _EditPhotoDialogState extends State<EditPhotoDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _locationNameController;
  late TextEditingController _regionController;
  late String _selectedCategory;
  bool _isSaving = false;
  String? _errorMessage;

  final FirestoreService _firestoreService = FirestoreService();

  @override
  void initState() {
    super.initState();
    _locationNameController = TextEditingController(text: widget.photo.location.name);
    _regionController = TextEditingController(text: widget.photo.location.region ?? '');
    
    // Capitalize category for dropdown matching
    final catRaw = widget.photo.category.isNotEmpty ? widget.photo.category : widget.photo.location.category;
    final matchedCat = categories.firstWhere(
      (c) => c.toLowerCase() == catRaw.toLowerCase(),
      orElse: () => categories.first,
    );
    _selectedCategory = matchedCat;
  }

  @override
  void dispose() {
    _locationNameController.dispose();
    _regionController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await _firestoreService.updatePhotoDetails(
        widget.photo.id,
        locationName: _locationNameController.text.trim(),
        region: _regionController.text.trim(),
        category: _selectedCategory,
      );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo details updated! ✏️'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
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
        constraints: const BoxConstraints(maxWidth: 440),
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
                      'Edit Photo Spot Details ✏️',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _isSaving ? null : () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Image preview thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    widget.photo.imageUrl,
                    height: 140,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 140,
                      color: AppColors.surfaceVariant,
                      child: const Icon(Icons.landscape, size: 48, color: AppColors.textSecondary),
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
                  height: 46,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveChanges,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('Save Changes',
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
