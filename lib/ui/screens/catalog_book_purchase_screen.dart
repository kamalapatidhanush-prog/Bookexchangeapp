import 'package:flutter/material.dart';

import '../../backend.dart';
import '../../models/catalog_book.dart';
import '../../models/library_models.dart';
import '../widgets/book_card.dart';
import '../widgets/empty_state.dart';
import 'book_detail_screen.dart';
import 'want_book_screen.dart';

class CatalogBookPurchaseScreen extends StatefulWidget {
  const CatalogBookPurchaseScreen({
    required this.book,
    this.service,
    super.key,
  });

  final CatalogBook book;
  final MySqlApiService? service;

  @override
  State<CatalogBookPurchaseScreen> createState() =>
      _CatalogBookPurchaseScreenState();
}

class _CatalogBookPurchaseScreenState extends State<CatalogBookPurchaseScreen> {
  late Future<List<MarketplaceListing>> _listingsFuture;

  MySqlApiService get _service => widget.service ?? MySqlApiService.instance;

  @override
  void initState() {
    super.initState();
    _listingsFuture = _loadListings();
  }

  Future<List<MarketplaceListing>> _loadListings() {
    return _service.getListings(query: widget.book.title, status: 'available');
  }

  void _retry() {
    setState(() => _listingsFuture = _loadListings());
  }

  Future<void> _requestBook() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => WantBookScreen(
          initialTitle: widget.book.title,
          initialAuthor: widget.book.author,
        ),
      ),
    );
  }

  Future<void> _openListing(MarketplaceListing listing) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            BookDetailScreen(listingId: listing.id, initialListing: listing),
      ),
    );
    if (mounted) _retry();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Buy with credits')),
      body: FutureBuilder<List<MarketplaceListing>>(
        future: _listingsFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorStateWidget(
              message: snapshot.error.toString().replaceFirst(
                'Exception: ',
                '',
              ),
              onRetry: _retry,
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final listings = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BookCoverWidget(
                    title: widget.book.title,
                    coverUrl: widget.book.coverUrl,
                    width: 84,
                    height: 124,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.book.title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        Text('by ${widget.book.author}'),
                        const SizedBox(height: 10),
                        const Text(
                          'Choose an available copy from a community seller. '
                          'The listed credit price and delivery details are '
                          'shown before you place an order.',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                listings.isEmpty
                    ? 'Available copies (0)'
                    : 'Available copies (${listings.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (listings.isEmpty) ...[
                EmptyStateWidget(
                  icon: Icons.menu_book_outlined,
                  title: 'No copies listed yet',
                  subtitle:
                      'There are no seller copies to buy right now. Request '
                      'this book from the community, or check again later.',
                  actionLabel: 'Request this book',
                  onAction: _requestBook,
                ),
                OutlinedButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Check again'),
                ),
              ] else
                ...listings.map(
                  (listing) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ListingCard(
                      listing: listing,
                      onTap: () => _openListing(listing),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
