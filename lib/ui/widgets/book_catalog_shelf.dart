import 'package:flutter/material.dart';

import '../../backend.dart';
import '../../models/catalog_book.dart';
import 'book_card.dart';

class BookCatalogShelf extends StatefulWidget {
  const BookCatalogShelf({super.key});

  @override
  State<BookCatalogShelf> createState() => _BookCatalogShelfState();
}

class _BookCatalogShelfState extends State<BookCatalogShelf> {
  late Future<List<CatalogBook>> _booksFuture;

  @override
  void initState() {
    super.initState();
    _booksFuture = MySqlApiService.instance.getFeaturedCatalogBooks();
  }

  void _retry() {
    setState(() {
      _booksFuture = MySqlApiService.instance.getFeaturedCatalogBooks();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<CatalogBook>>(
      future: _booksFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Book covers are temporarily unavailable.'),
                ),
                TextButton(onPressed: _retry, child: const Text('Retry')),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 250,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final books = snapshot.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Text('Popular books', style: theme.textTheme.titleMedium),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Book catalog picks · covers via Open Library. These are not seller listings.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            SizedBox(
              height: 270,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                scrollDirection: Axis.horizontal,
                itemCount: books.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) =>
                    _CatalogBookCard(book: books[index]),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CatalogBookCard extends StatelessWidget {
  const _CatalogBookCard({required this.book});

  final CatalogBook book;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 142,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              book.coverUrl,
              width: 142,
              height: 190,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  BookCoverWidget(title: book.title, width: 142, height: 190),
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Container(
                  width: 142,
                  height: 190,
                  color: theme.colorScheme.surfaceContainerHighest,
                  alignment: Alignment.center,
                  child: const CircularProgressIndicator(),
                );
              },
            ),
          ),
          const SizedBox(height: 7),
          Text(
            book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            book.author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}
