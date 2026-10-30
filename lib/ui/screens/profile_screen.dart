import 'package:flutter/material.dart';
import '../../backend.dart';
import '../../models/library_models.dart';
import '../widgets/empty_state.dart';
import 'book_detail_screen.dart';
import 'ledger_sheet.dart';
import 'saved_books_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    required this.isDarkMode,
    required this.onToggleTheme,
    required this.onSignOut,
    super.key,
  });

  final bool isDarkMode;
  final ValueChanged<bool> onToggleTheme;
  final VoidCallback onSignOut;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  UserProfile? _profile;
  List<MarketplaceListing> _myListings = [];
  int _savedBooksCount = 0;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final currentUserId = MySqlApiService.instance.currentUser?.id ?? '';
      final profileFuture = MySqlApiService.instance.getProfile();
      final myListingsFuture = MySqlApiService.instance.getListings(
        ownerId: currentUserId,
      );
      final savedBooksFuture = MySqlApiService.instance.getSavedBooks();

      final results = await Future.wait([
        profileFuture,
        myListingsFuture,
        savedBooksFuture,
      ]);

      if (mounted) {
        setState(() {
          _profile = results[0] as UserProfile;
          _myListings = results[1] as List<MarketplaceListing>;
          _savedBooksCount = (results[2] as List<Map<String, dynamic>>).length;
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

  Future<void> _showEditProfileDialog() async {
    if (_profile == null) return;
    final nameController = TextEditingController(text: _profile!.name);
    final locationController = TextEditingController(text: _profile!.location);
    final bioController = TextEditingController(text: _profile!.bio);

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Edit Profile'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Display Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: locationController,
                decoration: const InputDecoration(
                  labelText: 'Neighborhood / Meetup Area',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bioController,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Reader Bio'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );

    if (saved == true && mounted) {
      try {
        await MySqlApiService.instance.updateProfile(
          name: nameController.text.trim(),
          location: locationController.text.trim(),
          bio: bioController.text.trim(),
        );
        _loadProfile();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.toString())));
        }
      }
    }

    nameController.dispose();
    locationController.dispose();
    bioController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_errorMessage != null && _profile == null) {
      return Scaffold(
        body: ErrorStateWidget(message: _errorMessage!, onRetry: _loadProfile),
      );
    }

    final profile = _profile!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Reader Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit Profile',
            onPressed: _showEditProfileDialog,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadProfile,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // User Header
            Row(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text(
                    profile.name.isNotEmpty
                        ? profile.name[0].toUpperCase()
                        : 'R',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontSize: 22,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        profile.location,
                        style: TextStyle(
                          color: theme.colorScheme.secondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        profile.email,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (profile.bio.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                profile.bio,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 20),

            // Credit Balance Card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1B3B2B), Color(0xFF2D5A40)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Credit Balance',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(
                                Icons.stars_rounded,
                                color: Color(0xFFE2B96D),
                                size: 28,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${profile.credits} Credits',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Trebuchet MS',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.2),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => CreditLedgerSheet.show(context),
                        child: const Text('View Ledger'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Trust & Statistics Row
            Row(
              children: [
                _buildStatBox(
                  context,
                  label: 'Trust Rating',
                  value: profile.rating?.toStringAsFixed(1) ?? 'New',
                  icon: Icons.star_rounded,
                  color: const Color(0xFFD4A359),
                ),
                const SizedBox(width: 10),
                _buildStatBox(
                  context,
                  label: 'Books Sold',
                  value: '${profile.soldCount}',
                  icon: Icons.upload_rounded,
                  color: const Color(0xFF2D5A40),
                ),
                const SizedBox(width: 10),
                _buildStatBox(
                  context,
                  label: 'Purchased',
                  value: '${profile.purchasedCount}',
                  icon: Icons.download_rounded,
                  color: const Color(0xFF52796F),
                ),
              ],
            ),
            const SizedBox(height: 26),

            // My Listed Books
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'My Listed Books (${_myListings.length})',
                  style: theme.textTheme.titleMedium?.copyWith(fontSize: 17),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_myListings.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: Text(
                      'You have not listed any books yet.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ),
                ),
              )
            else
              for (final book in _myListings) ...[
                Card(
                  child: ListTile(
                    title: Text(
                      book.title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${book.author} · ${book.creditValue} credits · ${book.status}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BookDetailScreen(
                            listingId: book.id,
                            initialListing: book,
                          ),
                        ),
                      );
                      _loadProfile();
                    },
                  ),
                ),
                const SizedBox(height: 6),
              ],

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),

            // Settings Section
            SwitchListTile(
              title: const Text(
                'Dark Mode',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              secondary: Icon(
                widget.isDarkMode
                    ? Icons.dark_mode_outlined
                    : Icons.light_mode_outlined,
              ),
              value: widget.isDarkMode,
              onChanged: widget.onToggleTheme,
            ),
            ListTile(
              leading: const Icon(Icons.bookmark_border_rounded),
              title: const Text('Saved Books'),
              subtitle: Text('$_savedBooksCount saved for later'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const SavedBooksScreen(),
                  ),
                );
                _loadProfile();
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text(
                'Sign Out',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onTap: widget.onSignOut,
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildStatBox(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.5,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Trebuchet MS',
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
                fontFamily: 'Trebuchet MS',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
