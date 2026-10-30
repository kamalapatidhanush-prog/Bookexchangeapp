import 'package:flutter/material.dart';
import '../../backend.dart';
import '../../models/library_models.dart';

class WantBookScreen extends StatefulWidget {
  const WantBookScreen({super.key});

  @override
  State<WantBookScreen> createState() => _WantBookScreenState();
}

class _WantBookScreenState extends State<WantBookScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _authorController = TextEditingController();
  final _notesController = TextEditingController();

  String _category = 'Fiction';
  int _maxCredits = 10;
  bool _isSubmitting = false;
  String? _errorMessage;
  Future<List<WantedBook>>? _requestsFuture;

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

  @override
  void initState() {
    super.initState();
    _requestsFuture = _loadRequestedBooks();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<List<WantedBook>> _loadRequestedBooks() async {
    final currentUserId = MySqlApiService.instance.currentUser?.id ?? '';
    final wantedBooks = await MySqlApiService.instance.getWantedBooks();
    return wantedBooks.where((entry) => entry.userId == currentUserId).toList();
  }

  Future<void> _refreshRequests() async {
    setState(() {
      _requestsFuture = _loadRequestedBooks();
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await MySqlApiService.instance.createWantedBook(
        title: _titleController.text.trim(),
        author: _authorController.text.trim(),
        category: _category,
        maxCredits: _maxCredits,
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
      );

      if (mounted) {
        setState(() {
          _requestsFuture = _loadRequestedBooks();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your book request was posted to the community!'),
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Want This Book')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer.withValues(
                  alpha: 0.5,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    color: theme.colorScheme.secondary,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Community Request',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          'Looking for a book that isn\'t listed yet? Tell the community and members who own it can connect with you.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.grey.shade700,
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
                hintText: 'e.g. Klara and the Sun',
                prefixIcon: Icon(Icons.bookmark_outline_rounded),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Please enter the title you want'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _authorController,
              decoration: const InputDecoration(
                labelText: 'Author',
                hintText: 'e.g. Kazuo Ishiguro',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Please enter the author'
                  : null,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
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
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _maxCredits,
                    decoration: const InputDecoration(
                      labelText: 'Max Credits to Offer',
                      prefixIcon: Icon(Icons.stars_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(value: 5, child: Text('5 Credits')),
                      DropdownMenuItem(value: 8, child: Text('8 Credits')),
                      DropdownMenuItem(value: 10, child: Text('10 Credits')),
                      DropdownMenuItem(value: 12, child: Text('12 Credits')),
                      DropdownMenuItem(value: 15, child: Text('15 Credits')),
                      DropdownMenuItem(value: 20, child: Text('20 Credits')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _maxCredits = v);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes / Preferred Condition (Optional)',
                hintText:
                    'e.g. Looking for a hardcover copy to read with my book club...',
                alignLabelWithHint: true,
              ),
            ),
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
            const SizedBox(height: 18),
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
                  : const Icon(Icons.send_rounded),
              label: Text(
                _isSubmitting ? 'Posting Request...' : 'Post Wanted Request',
              ),
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Your open requests',
                  style: theme.textTheme.titleMedium?.copyWith(fontSize: 17),
                ),
                IconButton(
                  onPressed: _refreshRequests,
                  tooltip: 'Refresh requests',
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FutureBuilder<List<WantedBook>>(
              future: _requestsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Unable to load your requests: ${snapshot.error}',
                    ),
                  );
                }

                final requests = snapshot.data ?? const <WantedBook>[];
                if (requests.isEmpty) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Text(
                        'You have not posted a wanted-book request yet.',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ),
                  );
                }

                return Column(
                  children: [
                    for (final item in requests)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: theme.colorScheme.outline.withValues(
                              alpha: 0.2,
                            ),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              backgroundColor: const Color(0xFFE2EFE7),
                              child: const Icon(
                                Icons.search_rounded,
                                color: Color(0xFF1B3B2B),
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'by ${item.author} • ${item.category}',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(
                                            0xFFD4A359,
                                          ).withValues(alpha: 0.18),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          'Up to ${item.maxCredits} cr',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                            fontFamily: 'Trebuchet MS',
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        item.status.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () async {
                                final messenger = ScaffoldMessenger.maybeOf(
                                  context,
                                );
                                try {
                                  await MySqlApiService.instance
                                      .deleteWantedBook(item.id);
                                  if (!mounted || messenger == null) return;
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Request removed: ${item.title}',
                                      ),
                                    ),
                                  );
                                  _refreshRequests();
                                } catch (e) {
                                  if (!mounted || messenger == null) return;
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        e.toString().replaceFirst(
                                          'Exception: ',
                                          '',
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              },
                              tooltip: 'Remove request',
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
