import 'package:flutter/material.dart';
import '../../backend.dart';

class ReviewDialog extends StatefulWidget {
  const ReviewDialog({
    required this.exchangeId,
    required this.bookTitle,
    required this.partnerName,
    super.key,
  });

  final String exchangeId;
  final String bookTitle;
  final String partnerName;

  static Future<bool?> show(
    BuildContext context, {
    required String exchangeId,
    required String bookTitle,
    required String partnerName,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => ReviewDialog(
        exchangeId: exchangeId,
        bookTitle: bookTitle,
        partnerName: partnerName,
      ),
    );
  }

  @override
  State<ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<ReviewDialog> {
  int _rating = 5;
  final _reviewController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _reviewController.text.trim();
    if (text.isEmpty) {
      setState(
        () => _errorMessage = 'Please write a brief review for the community.',
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await MySqlApiService.instance.submitReview(
        exchangeId: widget.exchangeId,
        rating: _rating,
        review: text,
      );
      if (mounted) {
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
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.star_rounded, color: Color(0xFFD4A359), size: 28),
          const SizedBox(width: 8),
          const Text('Rate Order'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How was your order for "${widget.bookTitle}" from ${widget.partnerName}?',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (index) {
                  final star = index + 1;
                  return IconButton(
                    onPressed: () => setState(() => _rating = star),
                    icon: Icon(
                      star <= _rating
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: const Color(0xFFD4A359),
                      size: 36,
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reviewController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Community Review',
                hintText: 'Share your experience with the reader community.',
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Submit Review'),
        ),
      ],
    );
  }
}
