import 'package:flutter/material.dart';
import '../../backend.dart';
import '../../models/library_models.dart';
import '../theme.dart';
import '../widgets/book_card.dart';
import '../widgets/book_catalog_shelf.dart';
import '../widgets/empty_state.dart';
import 'book_detail_screen.dart';
import 'ledger_sheet.dart';
import 'list_book_screen.dart';
import 'want_book_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.onNavigateToTab, super.key});

  final ValueChanged<int> onNavigateToTab;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _homeListingLimit = 12;

  bool _isLoading = true;
  String? _errorMessage;
  int? _creditBalance;
  List<MarketplaceListing> _availableListings = [];
  List<WantedBook> _wantedBooks = [];
  MarketplaceOrder? _activeOrder;

  @override
  void initState() {
    super.initState();
    _loadHomeData();
  }

  Future<void> _loadHomeData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final creditsFuture = MySqlApiService.instance.getCredits();
      final listingsFuture = MySqlApiService.instance.getListings(
        status: 'available',
      );
      final wantedFuture = MySqlApiService.instance.getWantedBooks();
      final ordersFuture = MySqlApiService.instance.getMarketplaceOrders();

      final results = await Future.wait([
        creditsFuture,
        listingsFuture,
        wantedFuture,
        ordersFuture,
      ]);

      final creditAcc = results[0] as CreditAccount;
      final listings = results[1] as List<MarketplaceListing>;
      final wanted = results[2] as List<WantedBook>;
      final orders = results[3] as List<MarketplaceOrder>;

      MarketplaceOrder? active;
      for (final o in orders) {
        if (!o.isDelivered) {
          active = o;
          break;
        }
      }

      if (mounted) {
        setState(() {
          _creditBalance = creditAcc.balance;
          _availableListings = listings;
          _wantedBooks = wanted;
          _activeOrder = active;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userName = MySqlApiService.instance.currentUser?.name ?? 'Reader';

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadHomeData,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                sliver: SliverToBoxAdapter(
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: LeafLoreTheme.heroGradient,
                      borderRadius: BorderRadius.circular(
                        LeafLoreTheme.cardRadius,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: LeafLoreTheme.pinePrimary.withValues(
                            alpha: 0.18,
                          ),
                          blurRadius: 18,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Welcome back,',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                userName,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: Colors.white,
                                  fontSize: 25,
                                ),
                              ),
                            ],
                          ),
                        ),
                        InkWell(
                          onTap: () => CreditLedgerSheet.show(context),
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.stars_rounded,
                                  size: 18,
                                  color: Color(0xFFFFD98A),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _creditBalance?.toString() ?? '...',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Colors.white,
                                    fontFamily: 'Trebuchet MS',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              if (_errorMessage != null)
                SliverToBoxAdapter(
                  child: ErrorStateWidget(
                    message: _errorMessage!,
                    onRetry: _loadHomeData,
                  ),
                )
              else if (_isLoading)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                if (_activeOrder != null)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                    sliver: SliverToBoxAdapter(
                      child: _buildActiveOrderBanner(_activeOrder!),
                    ),
                  ),

                // Quick Action Cards
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        _buildQuickAction(
                          context,
                          icon: Icons.search_rounded,
                          label: 'Find Book',
                          color: theme.colorScheme.primary,
                          onTap: () => widget.onNavigateToTab(1),
                        ),
                        const SizedBox(width: 10),
                        _buildQuickAction(
                          context,
                          icon: Icons.add_box_outlined,
                          label: 'List Book',
                          color: const Color(0xFF2D5A40),
                          onTap: () async {
                            final res = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ListBookScreen(),
                              ),
                            );
                            if (res == true) _loadHomeData();
                          },
                        ),
                        const SizedBox(width: 10),
                        _buildQuickAction(
                          context,
                          icon: Icons.bookmark_add_outlined,
                          label: 'Want Book',
                          color: const Color(0xFF52796F),
                          onTap: () async {
                            final res = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const WantBookScreen(),
                              ),
                            );
                            if (res == true) _loadHomeData();
                          },
                        ),
                        const SizedBox(width: 10),
                        _buildQuickAction(
                          context,
                          icon: Icons.shopping_bag_outlined,
                          label: 'Orders',
                          color: const Color(0xFFB58032),
                          onTap: () => widget.onNavigateToTab(2),
                        ),
                      ],
                    ),
                  ),
                ),

                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Books in the marketplace',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 18,
                          ),
                        ),
                        TextButton(
                          onPressed: () => widget.onNavigateToTab(1),
                          child: const Text('See All'),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  sliver: _availableListings.isEmpty
                      ? SliverToBoxAdapter(
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                children: [
                                  const Icon(
                                    Icons.menu_book_rounded,
                                    size: 36,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(height: 10),
                                  const Text(
                                    'No books listed in community yet.',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Be the first to sell a book for credits!',
                                  ),
                                  const SizedBox(height: 14),
                                  FilledButton(
                                    onPressed: () async {
                                      final res = await Navigator.push<bool>(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const ListBookScreen(),
                                        ),
                                      );
                                      if (res == true) _loadHomeData();
                                    },
                                    child: const Text('List a Book'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      : SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final item = _availableListings[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: ListingCard(
                                  listing: item,
                                  onTap: () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => BookDetailScreen(
                                          listingId: item.id,
                                          initialListing: item,
                                        ),
                                      ),
                                    );
                                    _loadHomeData();
                                  },
                                ),
                              );
                            },
                            childCount:
                                _availableListings.length > _homeListingLimit
                                ? _homeListingLimit
                                : _availableListings.length,
                          ),
                        ),
                ),

                const SliverToBoxAdapter(child: BookCatalogShelf()),

                // Community Wanted Reads
                if (_wantedBooks.isNotEmpty) ...[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                    sliver: SliverToBoxAdapter(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Community Wanted Reads',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontSize: 18,
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              final res = await Navigator.push<bool>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const WantBookScreen(),
                                ),
                              );
                              if (res == true) _loadHomeData();
                            },
                            child: const Text('Post Request'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final item = _wantedBooks[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: Color(0xFFE2EFE7),
                                child: Icon(
                                  Icons.search,
                                  color: Color(0xFF1B3B2B),
                                ),
                              ),
                              title: Text(
                                item.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                'by ${item.author} · Requested by ${item.userName}',
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFFD4A359,
                                  ).withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(8),
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
                            ),
                          );
                        },
                        childCount: _wantedBooks.length > 4
                            ? 4
                            : _wantedBooks.length,
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Trebuchet MS',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveOrderBanner(MarketplaceOrder order) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF173C2D), Color(0xFF2A5547)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(LeafLoreTheme.cardRadius),
        boxShadow: [
          BoxShadow(
            color: LeafLoreTheme.pinePrimary.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.local_shipping_outlined,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.isSeller ? 'Your recent sale' : 'Your recent purchase',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  order.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                Text(
                  order.isPaid
                      ? 'Paid · awaiting shipment'
                      : order.isShipped
                      ? 'Shipped · on the way'
                      : 'Delivered',
                  style: const TextStyle(
                    color: Color(0xFFE7C77B),
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF173C2D),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            onPressed: () => widget.onNavigateToTab(2),
            child: const Text('View'),
          ),
        ],
      ),
    );
  }
}
