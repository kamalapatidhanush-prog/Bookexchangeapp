import 'package:flutter/material.dart';
import '../../backend.dart';
import '../../models/library_models.dart';
import '../widgets/book_card.dart';
import 'list_book_screen.dart';

class BookDetailScreen extends StatefulWidget {
  const BookDetailScreen({
    required this.listingId,
    this.initialListing,
    super.key,
  });

  final String listingId;
  final MarketplaceListing? initialListing;

  @override
  State<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends State<BookDetailScreen> {
  MarketplaceListing? _listing;
  bool _isLoading = true;
  String? _errorMessage;
  int _userCredits = 0;
  List<MarketplaceOrder> _userOrders = [];
  bool _isActionInProgress = false;
  bool _isSaved = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _listing = widget.initialListing;
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() => _isLoading = true);
    try {
      final listing = await MySqlApiService.instance.getListing(
        widget.listingId,
      );
      final creditsAcc = await MySqlApiService.instance.getCredits();
      final orders = await MySqlApiService.instance.getMarketplaceOrders();
      final savedBooks = await MySqlApiService.instance.getSavedBooks();

      if (mounted) {
        setState(() {
          _listing = listing;
          _userCredits = creditsAcc.balance;
          _userOrders = orders;
          _isSaved = savedBooks.any((book) => book['title'] == listing.title);
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

  Future<void> _handlePurchase() async {
    if (_listing == null) return;
    final listing = _listing!;
    final formKey = GlobalKey<FormState>();
    final controllers = <String, TextEditingController>{
      'recipient_name': TextEditingController(
        text: MySqlApiService.instance.currentUser?.name ?? '',
      ),
      'recipient_phone': TextEditingController(),
      'address_line1': TextEditingController(),
      'address_line2': TextEditingController(),
      'city': TextEditingController(),
      'region': TextEditingController(),
      'postal_code': TextEditingController(),
      'country': TextEditingController(),
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delivery address'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Your ${listing.creditValue} credits transfer to the seller immediately. The seller pays shipping; no extra credits are charged.',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  _addressField(
                    controllers,
                    'recipient_name',
                    'Recipient name',
                  ),
                  _addressField(controllers, 'recipient_phone', 'Phone number'),
                  _addressField(controllers, 'address_line1', 'Address line 1'),
                  _addressField(
                    controllers,
                    'address_line2',
                    'Address line 2 (optional)',
                    required: false,
                  ),
                  _addressField(controllers, 'city', 'City'),
                  _addressField(controllers, 'region', 'State / region'),
                  _addressField(controllers, 'postal_code', 'Postal code'),
                  _addressField(controllers, 'country', 'Country'),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: Text('Buy for ${listing.creditValue} credits'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isActionInProgress = true);
      try {
        await MySqlApiService.instance.createMarketplaceOrder(
          listingId: listing.id,
          idempotencyKey:
              '${listing.id}-${DateTime.now().microsecondsSinceEpoch}',
          shippingAddress: {
            for (final entry in controllers.entries)
              entry.key: entry.value.text.trim(),
          },
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Order placed. The seller has been notified.'),
              backgroundColor: Color(0xFF1B3B2B),
            ),
          );
          await _loadDetails();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.toString().replaceFirst('Exception: ', '')),
            ),
          );
        }
      } finally {
        for (final controller in controllers.values) {
          controller.dispose();
        }
        if (mounted) setState(() => _isActionInProgress = false);
      }
    } else {
      for (final controller in controllers.values) {
        controller.dispose();
      }
    }
  }

  Widget _addressField(
    Map<String, TextEditingController> controllers,
    String key,
    String label, {
    bool required = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controllers[key],
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(labelText: label),
        validator: !required
            ? null
            : (value) =>
                  value == null || value.trim().isEmpty ? 'Required' : null,
      ),
    );
  }

  Future<void> _handleDeleteListing() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Listing'),
        content: const Text('Remove this book from the marketplace?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await MySqlApiService.instance.deleteListing(widget.listingId);
        if (mounted) {
          Navigator.pop(context, true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.toString())));
        }
      }
    }
  }

  Future<void> _toggleSavedBook() async {
    final listing = _listing;
    if (listing == null || _isSaving) return;

    setState(() => _isSaving = true);
    try {
      if (_isSaved) {
        await MySqlApiService.instance.removeSavedBook(listing.title);
      } else {
        await MySqlApiService.instance.saveBook(
          title: listing.title,
          author: listing.author,
          category: listing.category,
          coverUrl: listing.coverImageUrl,
        );
      }
      if (!mounted) return;
      setState(() => _isSaved = !_isSaved);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isSaved
                ? 'Book saved for later.'
                : 'Book removed from saved books.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading && _listing == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_errorMessage != null && _listing == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_errorMessage!),
              const SizedBox(height: 12),
              FilledButton(onPressed: _loadDetails, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final listing = _listing!;
    final currentUserId = MySqlApiService.instance.currentUser?.id ?? '';
    final isOwner = listing.ownerId == currentUserId;

    // Find any existing active order for this listing involving current user
    MarketplaceOrder? activeOrder;
    for (final o in _userOrders) {
      if (o.listingId == listing.id) {
        activeOrder = o;
        break;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(listing.title),
        actions: [
          IconButton(
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _isSaved
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                  ),
            tooltip: _isSaved ? 'Remove saved book' : 'Save book',
            onPressed: _isLoading || _isSaving ? null : _toggleSavedBook,
          ),
          if (isOwner && listing.status == 'available')
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Delete Listing',
              onPressed: _handleDeleteListing,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          Center(
            child: BookCoverWidget(
              title: listing.title,
              coverUrl: listing.coverImageUrl,
              width: 140,
              height: 200,
              borderRadius: 12,
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              listing.title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium?.copyWith(fontSize: 24),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              'by ${listing.author}',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.secondary,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildBadge(theme, Icons.category_outlined, listing.category),
              const SizedBox(width: 8),
              _buildBadge(
                theme,
                Icons.verified_outlined,
                listing.bookCondition,
              ),
              const SizedBox(width: 8),
              _buildBadge(
                theme,
                Icons.local_shipping_outlined,
                'Seller-paid shipping',
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Owner Info Card
          Card(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.5,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(
                      (listing.ownerName ?? 'R')[0].toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          listing.ownerName ?? 'Community Member',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Marketplace seller',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (listing.ownerRating != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4A359).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 16,
                            color: Color(0xFFD4A359),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            listing.ownerRating!.toStringAsFixed(1),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'About this copy',
            style: theme.textTheme.titleMedium?.copyWith(fontSize: 17),
          ),
          const SizedBox(height: 8),
          Text(
            listing.description,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontSize: 15,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 36),
          // Dynamic Action Button
          _buildActionButton(context, theme, isOwner, activeOrder),
        ],
      ),
    );
  }

  Widget _buildBadge(ThemeData theme, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
              fontFamily: 'Trebuchet MS',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    ThemeData theme,
    bool isOwner,
    MarketplaceOrder? activeOrder,
  ) {
    final listing = _listing!;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_isActionInProgress) {
      return const Center(child: CircularProgressIndicator());
    }

    if (isOwner) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 20),
            SizedBox(width: 8),
            Text(
              'This is your listing',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ],
        ),
      );
    }

    if (activeOrder != null) {
      final message = activeOrder.isDelivered
          ? 'Delivered. This book is now part of your library.'
          : activeOrder.isShipped
          ? 'Your book is on the way${activeOrder.trackingNumber == null ? '.' : ' · Tracking ${activeOrder.trackingNumber}'}'
          : 'Order placed. The seller will ship your book to the address you provided.';
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.local_shipping_outlined),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }

    if (listing.status != 'available') {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: Text(
            listing.status == 'sold'
                ? 'This book has been sold.'
                : 'This book is currently unavailable.',
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    final hasEnoughCredits = _userCredits >= listing.creditValue;
    if (!hasEnoughCredits) {
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Color(0xFF92400E)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Requires ${listing.creditValue} credits. You currently have $_userCredits credits.',
                    style: const TextStyle(
                      color: Color(0xFF92400E),
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final listed = await Navigator.push<bool>(
                context,
                MaterialPageRoute(builder: (_) => const ListBookScreen()),
              );
              if (listed == true && mounted) {
                await _loadDetails();
              }
            },
            icon: const Icon(Icons.add),
            label: const Text('Sell a book to earn credits'),
          ),
        ],
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        onPressed: _handlePurchase,
        icon: const Icon(Icons.shopping_bag_outlined),
        label: Text('Buy now · ${listing.creditValue} credits'),
      ),
    );
  }
}
