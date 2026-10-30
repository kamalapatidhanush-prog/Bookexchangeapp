import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../backend.dart';
import '../theme.dart';

class ListBookScreen extends StatefulWidget {
  const ListBookScreen({super.key});

  @override
  State<ListBookScreen> createState() => _ListBookScreenState();
}

class _ListBookScreenState extends State<ListBookScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _authorController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _imagePicker = ImagePicker();
  XFile? _coverImage;
  String? _uploadedCoverUrl;

  String _category = 'Fiction';
  String _condition = 'Very Good';
  int _creditValue = 10;
  bool _isSubmitting = false;
  String? _errorMessage;

  static const _categories = [
    'Fiction',
    'Non-fiction',
    'Mystery',
    'Romance',
    'Sci-Fi',
    'Biography',
    'History',
    'Self-Help',
    'Philosophy',
    'Fantasy',
  ];

  static const _conditions = ['New', 'Like New', 'Very Good', 'Good', 'Fair'];

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickCoverImage() async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 2200,
        imageQuality: 85,
      );
      if (image != null && mounted) {
        setState(() {
          _coverImage = image;
          _uploadedCoverUrl = null;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      var coverUrl = _uploadedCoverUrl;
      final image = _coverImage;
      if (image != null && coverUrl == null) {
        final bytes = await image.readAsBytes();
        coverUrl = await MySqlApiService.instance.uploadBookCover(
          bytes: bytes,
          fileName: image.name,
          mimeType: image.mimeType ?? 'image/jpeg',
        );
        _uploadedCoverUrl = coverUrl;
      }
      await MySqlApiService.instance.createListing(
        title: _titleController.text.trim(),
        author: _authorController.text.trim(),
        description: _descriptionController.text.trim(),
        category: _category,
        condition: _condition,
        creditValue: _creditValue,
        coverUrl: coverUrl,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.local_shipping_outlined, color: Color(0xFFD4A359)),
                SizedBox(width: 8),
                Expanded(child: Text('Book added to the marketplace.')),
              ],
            ),
            backgroundColor: Color(0xFF1B3B2B),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sell a Book')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LeafLoreTheme.heroGradient,
                borderRadius: BorderRadius.circular(LeafLoreTheme.cardRadius),
                boxShadow: [
                  BoxShadow(
                    color: LeafLoreTheme.pinePrimary.withValues(alpha: 0.15),
                    blurRadius: 14,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.stars_rounded,
                    color: Color(0xFFFFD98A),
                    size: 30,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ship to the buyer',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'The seller pays to ship the book. Credits transfer to you immediately when it sells; add the carrier and tracking number after dispatch.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Book Title',
                hintText: 'e.g. Pachinko',
                prefixIcon: Icon(Icons.menu_book_outlined),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Please enter the book title'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _authorController,
              decoration: const InputDecoration(
                labelText: 'Author',
                hintText: 'e.g. Min Jin Lee',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Please enter the author name'
                  : null,
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final categoryField = DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: _categories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _category = v);
                  },
                );
                final conditionField = DropdownButtonFormField<String>(
                  initialValue: _condition,
                  decoration: const InputDecoration(
                    labelText: 'Condition',
                    prefixIcon: Icon(Icons.verified_outlined),
                  ),
                  items: _conditions
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _condition = v);
                  },
                );

                if (constraints.maxWidth < 480) {
                  return Column(
                    children: [
                      categoryField,
                      const SizedBox(height: 14),
                      conditionField,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: categoryField),
                    const SizedBox(width: 12),
                    Expanded(child: conditionField),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<int>(
              initialValue: _creditValue,
              decoration: const InputDecoration(
                labelText: 'Asking price (up to 20 credits)',
                prefixIcon: Icon(Icons.stars_outlined),
              ),
              items: List.generate(
                20,
                (index) => DropdownMenuItem(
                  value: index + 1,
                  child: Text(
                    '${index + 1} ${index == 0 ? 'Credit' : 'Credits'}',
                  ),
                ),
              ),
              onChanged: (v) {
                if (v != null) setState(() => _creditValue = v);
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _descriptionController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Book Description & Notes',
                hintText:
                    'Share edition details, condition specifics, or why you recommend this book...',
                alignLabelWithHint: true,
              ),
              validator: (v) => (v == null || v.trim().length < 10)
                  ? 'Please provide at least a brief description (10+ chars)'
                  : null,
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _isSubmitting ? null : _pickCoverImage,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Add a book cover photo'),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Cover photos appear on your book card in Home and Discover.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            if (_coverImage case final image?) ...[
              const SizedBox(height: 8),
              FutureBuilder<Uint8List>(
                future: image.readAsBytes(),
                builder: (context, snapshot) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: snapshot.hasData
                      ? Image.memory(
                          snapshot.data!,
                          width: 48,
                          height: 64,
                          fit: BoxFit.cover,
                        )
                      : const SizedBox(
                          width: 48,
                          height: 64,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                  title: Text(
                    image.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: const Text('JPEG, PNG, or WebP · maximum 8 MB'),
                  trailing: IconButton(
                    tooltip: 'Remove cover photo',
                    onPressed: _isSubmitting
                        ? null
                        : () => setState(() {
                            _coverImage = null;
                            _uploadedCoverUrl = null;
                          }),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: Colors.red.shade900, fontSize: 13),
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _isSubmitting ? null : _submit,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.publish_rounded),
              label: Text(
                _isSubmitting
                    ? 'Publishing to Community...'
                    : 'Publish Listing',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
