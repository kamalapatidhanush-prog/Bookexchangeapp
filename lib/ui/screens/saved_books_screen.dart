import 'package:flutter/material.dart';

import '../../backend.dart';
import '../widgets/empty_state.dart';

class SavedBooksScreen extends StatefulWidget {
  const SavedBooksScreen({super.key});

  @override
  State<SavedBooksScreen> createState() => _SavedBooksScreenState();
}

class _SavedBooksScreenState extends State<SavedBooksScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _savedBooks = [];

  @override
  void initState() {
    super.initState();
    _loadSavedBooks();
  }

  Future<void> _loadSavedBooks() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final books = await MySqlApiService.instance.getSavedBooks();
      if (mounted) {
        setState(() {
          _savedBooks = books;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _removeSavedBook(String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove Saved Book'),
        content: Text('Remove "$title" from your saved list?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await MySqlApiService.instance.removeSavedBook(title);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Saved book removed.')));
        _loadSavedBooks();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Books'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh saved books',
            onPressed: _loadSavedBooks,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_errorMessage!),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _loadSavedBooks,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : _savedBooks.isEmpty
          ? const EmptyStateWidget(
              icon: Icons.bookmark_border_rounded,
              title: 'No saved books yet',
              subtitle:
                  'Books you save from a listing will appear here for later.',
            )
          : RefreshIndicator(
              onRefresh: _loadSavedBooks,
              child: ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: _savedBooks.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final item = _savedBooks[index];
                  final title = (item['title'] ?? 'Untitled Book').toString();
                  final author = (item['author'] ?? 'Unknown Author')
                      .toString();
                  final category = (item['category'] ?? 'General').toString();

                  return Card(
                    child: ListTile(
                      leading: Container(
                        width: 52,
                        height: 72,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer
                              .withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.book_rounded,
                          color: Color(0xFF1B3B2B),
                        ),
                      ),
                      title: Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('$author · $category'),
                      trailing: IconButton(
                        tooltip: 'Remove saved book',
                        icon: const Icon(
                          Icons.bookmark_remove_outlined,
                          color: Colors.red,
                        ),
                        onPressed: () => _removeSavedBook(title),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
