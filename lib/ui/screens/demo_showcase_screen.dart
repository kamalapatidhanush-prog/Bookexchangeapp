import 'package:flutter/material.dart';

import '../theme.dart';

class DemoShowcaseScreen extends StatefulWidget {
  const DemoShowcaseScreen({required this.onExit, super.key});

  final VoidCallback onExit;

  @override
  State<DemoShowcaseScreen> createState() => _DemoShowcaseScreenState();
}

class _DemoShowcaseScreenState extends State<DemoShowcaseScreen> {
  static const _books = [
    _DemoBook('The Hobbit', 'J.R.R. Tolkien', 'Fantasy', Color(0xFF315B43)),
    _DemoBook(
      'Pride and Prejudice',
      'Jane Austen',
      'Romance',
      Color(0xFF9B5967),
    ),
    _DemoBook(
      'The Great Gatsby',
      'F. Scott Fitzgerald',
      'Classics',
      Color(0xFF345178),
    ),
    _DemoBook('Dune', 'Frank Herbert', 'Sci-Fi', Color(0xFFB36B37)),
    _DemoBook('The Alchemist', 'Paulo Coelho', 'Fiction', Color(0xFF96783A)),
    _DemoBook(
      'Little Women',
      'Louisa May Alcott',
      'Classics',
      Color(0xFF775B83),
    ),
    _DemoBook(
      'The Book Thief',
      'Markus Zusak',
      'Historical',
      Color(0xFF53677D),
    ),
    _DemoBook('Pachinko', 'Min Jin Lee', 'Historical', Color(0xFF9A5942)),
    _DemoBook(
      'The Silent Patient',
      'Alex Michaelides',
      'Mystery',
      Color(0xFF426E69),
    ),
    _DemoBook('Atomic Habits', 'James Clear', 'Non-fiction', Color(0xFF637842)),
  ];

  static const _categories = [
    'All',
    'Classics',
    'Fantasy',
    'Fiction',
    'Historical',
    'Mystery',
    'Non-fiction',
    'Romance',
    'Sci-Fi',
  ];

  static const _listingBookTitles = [
    'The Hobbit',
    'Pride and Prejudice',
    'Dune',
    'The Book Thief',
    'Atomic Habits',
  ];

  final _searchController = TextEditingController();
  int _tabIndex = 0;
  String _category = 'All';
  String _query = '';
  final Set<String> _savedTitles = {};

  List<_DemoBook> get _filteredBooks {
    final query = _query.toLowerCase();
    return _books
        .where((book) {
          final matchesCategory =
              _category == 'All' || book.category == _category;
          final matchesQuery =
              query.isEmpty ||
              book.title.toLowerCase().contains(query) ||
              book.author.toLowerCase().contains(query) ||
              book.category.toLowerCase().contains(query);
          return matchesCategory && matchesQuery;
        })
        .toList(growable: false);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['Home', 'Discover', 'Orders', 'Activity', 'Profile'];
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_tabIndex]),
        leading: IconButton(
          tooltip: 'Exit demo',
          onPressed: widget.onExit,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: [
          IconButton(
            tooltip: 'Exit demo',
            onPressed: widget.onExit,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: [
          _homeTab(context),
          _discoverTab(context),
          _ordersTab(context),
          _activityTab(context),
          _profileTab(context),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            color: const Color(0xFFFFF1D6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: const Text(
              'OFFLINE DEMO  ·  Sample books and activity only; no real orders or payments',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF674B1D),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          NavigationBar(
            selectedIndex: _tabIndex,
            onDestinationSelected: (index) => setState(() => _tabIndex = index),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.explore_outlined),
                selectedIcon: Icon(Icons.explore_rounded),
                label: 'Discover',
              ),
              NavigationDestination(
                icon: Icon(Icons.shopping_bag_outlined),
                selectedIcon: Icon(Icons.shopping_bag_rounded),
                label: 'Orders',
              ),
              NavigationDestination(
                icon: Icon(Icons.history_outlined),
                selectedIcon: Icon(Icons.history_rounded),
                label: 'Activity',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'Profile',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _homeTab(BuildContext context) {
    final theme = Theme.of(context);
    final listings = _listingBooks;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LeafLoreTheme.heroGradient,
            borderRadius: BorderRadius.circular(LeafLoreTheme.cardRadius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'WELCOME TO LEAF & LORE',
                style: TextStyle(
                  color: Color(0xFFFFD98A),
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Books found.\nStories shared.',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Discover a new favorite and meet the readers in your community.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () => setState(() => _tabIndex = 1),
                icon: const Icon(Icons.explore_outlined),
                label: const Text('Explore books'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        _sectionTitle(context, 'Popular books', '10 reader favorites'),
        const SizedBox(height: 10),
        SizedBox(
          height: 224,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _books.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final book = _books[index];
              return SizedBox(
                width: 118,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _showBookDetails(book),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DemoBookCover(book: book, width: 118, height: 158),
                      const SizedBox(height: 7),
                      Text(
                        book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge,
                      ),
                      Text(
                        book.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 18),
        _sectionTitle(context, 'Community marketplace', 'Sample listings'),
        const SizedBox(height: 4),
        const Text(
          'Demo examples only — these books are not actually for sale.',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 8),
        for (final book in listings.take(3)) _listingCard(book),
      ],
    );
  }

  Widget _discoverTab(BuildContext context) {
    final books = _filteredBooks;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value.trim()),
            decoration: InputDecoration(
              hintText: 'Search title, author, genre...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: _categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final category = _categories[index];
              return ChoiceChip(
                label: Text(category),
                selected: category == _category,
                onSelected: (_) => setState(() => _category = category),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Book catalog and sample seller listings',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        Expanded(
          child: books.isEmpty
              ? const Center(child: Text('No demo books match that search.'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                  itemCount: books.length,
                  itemBuilder: (context, index) {
                    final book = books[index];
                    return _bookListCard(book);
                  },
                ),
        ),
      ],
    );
  }

  Widget _ordersTab(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text('Order tracking preview', style: theme.textTheme.titleLarge),
        const SizedBox(height: 6),
        const Text(
          'Example order cards to demonstrate the design. No shipment exists.',
        ),
        const SizedBox(height: 14),
        _sampleOrderCard(
          context,
          book: _books[0],
          status: 'Shipped',
          detail: 'Tracking updates would appear here.',
          icon: Icons.local_shipping_outlined,
        ),
        _sampleOrderCard(
          context,
          book: _books[3],
          status: 'Delivered',
          detail: 'Delivery confirmation and review preview.',
          icon: Icons.check_circle_outline,
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.stars_rounded, color: Color(0xFFD4A359)),
            title: const Text('Sample wallet balance'),
            subtitle: const Text('Demo credits have no cash value.'),
            trailing: const Text(
              '120',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  Widget _activityTab(BuildContext context) {
    final activities = [
      ('New book listed', 'Maya shared The Hobbit with the community.'),
      ('Order shipped', 'A sample order is on its way to a reader.'),
      ('Book saved', 'A reader added Pride and Prejudice to their list.'),
      ('Review received', 'A community member left a five-star review.'),
      ('Wanted book posted', 'Someone is looking for a new weekend read.'),
    ];
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(
          'Community activity',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        const Text('Illustrative activity for the offline presentation.'),
        const SizedBox(height: 12),
        for (final (title, subtitle) in activities)
          Card(
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.auto_stories_outlined),
              ),
              title: Text(title),
              subtitle: Text(subtitle),
              trailing: const Icon(Icons.chevron_right),
            ),
          ),
      ],
    );
  }

  Widget _profileTab(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Center(
          child: Column(
            children: [
              const CircleAvatar(
                radius: 42,
                backgroundColor: Color(0xFFE2EFE7),
                child: Icon(
                  Icons.person_rounded,
                  size: 44,
                  color: Color(0xFF1B3B2B),
                ),
              ),
              const SizedBox(height: 10),
              Text('Alex Reader', style: theme.textTheme.titleLarge),
              const Text('Demo profile · Maplewood'),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: const [
                _DemoStat(value: '4.9', label: 'Rating'),
                _DemoStat(value: '12', label: 'Books shared'),
                _DemoStat(value: '8', label: 'Orders'),
              ],
            ),
          ),
        ),
        Card(
          child: Column(
            children: [
              const ListTile(
                leading: Icon(Icons.bookmark_outline),
                title: Text('Saved books'),
                subtitle: Text('Your demo reading list'),
              ),
              for (final title in _savedTitles.take(3))
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text(title),
                ),
              if (_savedTitles.isEmpty)
                const ListTile(
                  dense: true,
                  title: Text(
                    'Save a title from Discover to preview this list.',
                  ),
                ),
            ],
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Presentation mode'),
            subtitle: const Text(
              'All displayed accounts, activity, credits, and orders are sample data stored only for this demo session.',
            ),
          ),
        ),
      ],
    );
  }

  Widget _bookListCard(_DemoBook book) {
    final isListing = _listingBookTitles.contains(book.title);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showBookDetails(book),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DemoBookCover(book: book, width: 74, height: 104),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: [
                        _tag(book.category),
                        if (isListing) _tag('DEMO LISTING'),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      book.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isListing
                          ? 'Sample community book · 10 credits'
                          : 'Popular catalog pick',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        tooltip: _savedTitles.contains(book.title)
                            ? 'Remove from saved'
                            : 'Save book',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() {
                          if (!_savedTitles.add(book.title)) {
                            _savedTitles.remove(book.title);
                          }
                        }),
                        icon: Icon(
                          _savedTitles.contains(book.title)
                              ? Icons.bookmark
                              : Icons.bookmark_border,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _listingCard(_DemoBook book) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(10),
        leading: _DemoBookCover(book: book, width: 48, height: 66),
        title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${book.author} · Demo listing only'),
        trailing: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.stars_rounded, color: Color(0xFFD4A359), size: 18),
            Text('10 cr'),
          ],
        ),
        onTap: () => _showBookDetails(book),
      ),
    );
  }

  Widget _sampleOrderCard(
    BuildContext context, {
    required _DemoBook book,
    required String status,
    required String detail,
    required IconData icon,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DemoBookCover(book: book, width: 58, height: 82),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        icon,
                        size: 17,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          status,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    book.title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    book.author,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(detail, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBookDetails(_DemoBook book) {
    final isListing = _listingBookTitles.contains(book.title);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: _DemoBookCover(book: book, width: 132, height: 184),
              ),
              const SizedBox(height: 14),
              Text(book.title, style: Theme.of(context).textTheme.titleLarge),
              Text('by ${book.author} · ${book.category}'),
              const SizedBox(height: 12),
              Text(
                isListing
                    ? 'This sample listing demonstrates the book detail and community exchange flow. It is not a real seller listing.'
                    : 'A popular reader pick in the Leaf & Lore demo catalog.',
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    isListing ? 'Demo preview · no order placed' : 'Done',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title, String subtitle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _tag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFE2EFE7),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: Color(0xFF1B3B2B),
        ),
      ),
    );
  }

  List<_DemoBook> get _listingBooks => _books
      .where((book) => _listingBookTitles.contains(book.title))
      .toList(growable: false);
}

class _DemoStat extends StatelessWidget {
  const _DemoStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _DemoBookCover extends StatelessWidget {
  const _DemoBookCover({
    required this.book,
    required this.width,
    required this.height,
  });

  final _DemoBook book;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [book.color, Color.lerp(book.color, Colors.black, 0.45)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(9),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 6,
            offset: const Offset(1, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(
            Icons.auto_stories_rounded,
            size: width < 60 ? 16 : 21,
            color: Colors.white70,
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                book.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: width < 60
                      ? 8
                      : width < 100
                      ? 10
                      : 12,
                  height: 1.12,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                book.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: width < 60 ? 6 : 8,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DemoBook {
  const _DemoBook(this.title, this.author, this.category, this.color);

  final String title;
  final String author;
  final String category;
  final Color color;
}
