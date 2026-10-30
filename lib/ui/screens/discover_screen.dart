import 'dart:async';
import 'package:flutter/material.dart';
import '../../backend.dart';
import '../../models/library_models.dart';
import '../theme.dart';
import '../widgets/book_card.dart';
import '../widgets/book_catalog_shelf.dart';
import '../widgets/empty_state.dart';
import 'book_detail_screen.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _searchController = TextEditingController();
  Timer? _debounceTimer;

  String _selectedCategory = 'All';
  String _selectedCondition = 'All';
  String _query = '';
  bool _isLoading = true;
  String? _errorMessage;
  List<MarketplaceListing> _listings = [];

  static const _categories = [
    'All',
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
    _fetchListings();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String text) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      setState(() {
        _query = text.trim();
      });
      _fetchListings();
    });
  }

  Future<void> _fetchListings() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await MySqlApiService.instance.getListings(
        category: _selectedCategory != 'All' ? _selectedCategory : null,
        query: _query.isNotEmpty ? _query : null,
        status: 'available',
      );

      if (mounted) {
        setState(() {
          _listings = results;
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

  List<MarketplaceListing> get _filteredListings {
    if (_selectedCondition == 'All') return _listings;
    return _listings
        .where((item) => item.bookCondition == _selectedCondition)
        .toList();
  }

  Future<void> _showFilterSheet() async {
    final theme = Theme.of(context);
    final chosenCondition = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Filter by Condition',
                style: theme.textTheme.titleMedium?.copyWith(fontSize: 18),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children:
                    ['All', 'New', 'Like New', 'Very Good', 'Good', 'Fair'].map(
                      (c) {
                        final isSelected = c == _selectedCondition;
                        return ChoiceChip(
                          label: Text(c),
                          selected: isSelected,
                          onSelected: (_) => Navigator.pop(ctx, c),
                        );
                      },
                    ).toList(),
              ),
            ],
          ),
        );
      },
    );

    if (chosenCondition != null && chosenCondition != _selectedCondition) {
      setState(() => _selectedCondition = chosenCondition);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayedListings = _filteredListings;

    return Scaffold(
      appBar: AppBar(title: const Text('Discover Books')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(LeafLoreTheme.cardRadius),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        hintText: 'Search title, author, genre...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  _onSearchChanged('');
                                },
                              )
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LeafLoreTheme.heroGradient,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      onPressed: _showFilterSheet,
                      icon: const Icon(Icons.tune_rounded, color: Colors.white),
                      tooltip: 'Filter options',
                    ),
                  ),
                ],
              ),
            ),
          ),

          SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final cat = _categories[index];
                final isSelected = cat == _selectedCategory;
                return ChoiceChip(
                  label: Text(cat),
                  selected: isSelected,
                  selectedColor: theme.colorScheme.primary,
                  labelStyle: TextStyle(
                    color: isSelected
                        ? Colors.white
                        : theme.colorScheme.onSurface,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    fontFamily: 'Trebuchet MS',
                    fontSize: 12.5,
                  ),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedCategory = cat);
                      _fetchListings();
                    }
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 10),

          // Active filter chip reminder
          if (_selectedCondition != 'All')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  Text(
                    'Condition: $_selectedCondition',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => setState(() => _selectedCondition = 'All'),
                    child: const Icon(Icons.close, size: 16),
                  ),
                ],
              ),
            ),

          // Results List
          Expanded(
            child: RefreshIndicator(
              onRefresh: _fetchListings,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  const SliverToBoxAdapter(child: BookCatalogShelf()),
                  if (_isLoading)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_errorMessage != null)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: ErrorStateWidget(
                        message: _errorMessage!,
                        onRetry: _fetchListings,
                      ),
                    )
                  else if (displayedListings.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyStateWidget(
                        icon: Icons.search_off_rounded,
                        title: 'No books found',
                        subtitle: _query.isNotEmpty
                            ? 'No listings matched "$_query". Try different keywords or browse all categories.'
                            : 'No books currently available in this category.',
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final listing = displayedListings[index];
                          return Padding(
                            padding: EdgeInsets.only(
                              bottom: index == displayedListings.length - 1
                                  ? 0
                                  : 10,
                            ),
                            child: ListingCard(
                              listing: listing,
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => BookDetailScreen(
                                      listingId: listing.id,
                                      initialListing: listing,
                                    ),
                                  ),
                                );
                                _fetchListings();
                              },
                            ),
                          );
                        }, childCount: displayedListings.length),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
