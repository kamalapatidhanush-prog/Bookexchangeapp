import 'package:flutter/material.dart';
import '../../backend.dart';
import '../../models/library_models.dart';
import 'credit_store_screen.dart';

class CreditLedgerSheet extends StatefulWidget {
  const CreditLedgerSheet({super.key, this.service});

  final MySqlApiService? service;

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CreditLedgerSheet(),
    );
  }

  @override
  State<CreditLedgerSheet> createState() => _CreditLedgerSheetState();
}

class _CreditLedgerSheetState extends State<CreditLedgerSheet> {
  MySqlApiService get _service => widget.service ?? MySqlApiService.instance;
  late Future<CreditAccount> _creditsFuture;
  CreditAccount? _account;
  String? _nextCursor;
  String? _loadMoreError;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _creditsFuture = _loadFirstPage();
  }

  Future<CreditAccount> _loadFirstPage() async {
    final account = await _service.getCredits();
    if (mounted) {
      setState(() {
        _account = account;
        _nextCursor = account.nextCursor;
        _loadMoreError = null;
      });
    }
    return account;
  }

  Future<void> _refresh() async {
    final future = _loadFirstPage();
    setState(() {
      _nextCursor = null;
      _creditsFuture = future;
    });
    try {
      await future;
    } catch (_) {
      // FutureBuilder displays the error and keeps the retry action available.
    }
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    final current = _account;
    if (cursor == null || current == null || _loadingMore) return;

    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
    });
    try {
      final page = await _service.getCredits(cursor: cursor);
      if (!mounted) return;
      final existingIds = current.ledger.map((entry) => entry.id).toSet();
      final merged = CreditAccount(
        balance: page.balance,
        summary: page.summary,
        ledger: [
          ...current.ledger,
          ...page.ledger.where((entry) => !existingIds.contains(entry.id)),
        ],
        hasMore: page.hasMore,
        nextCursor: page.nextCursor,
      );
      setState(() {
        _account = merged;
        _nextCursor = page.nextCursor;
        _creditsFuture = Future.value(merged);
      });
    } catch (error) {
      if (mounted) setState(() => _loadMoreError = error.toString());
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Credit Ledger', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 2),
                      Text(
                        'Append-only record of all balance changes',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<CreditAccount>(
              future: _creditsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Unable to load ledger: ${snapshot.error}',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _refresh,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final account = _account ?? snapshot.data!;
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.stars_rounded,
                              size: 40,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 14),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${account.balance} Credits',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onPrimaryContainer,
                                    fontFamily: 'Trebuchet MS',
                                  ),
                                ),
                                Text(
                                  'Current Available Balance',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: theme.colorScheme.onPrimaryContainer
                                        .withValues(alpha: 0.8),
                                    fontFamily: 'Trebuchet MS',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const CreditStoreScreen(),
                            ),
                          ),
                          icon: const Icon(Icons.add_card_rounded),
                          label: const Text('Buy Credits'),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Credit activity',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _summaryChip('Earned', account.summary.earned),
                          _summaryChip('Purchased', account.summary.purchased),
                          _summaryChip('Spent', account.summary.spent),
                          _summaryChip('Held', account.summary.held),
                          _summaryChip('Refunded', account.summary.refunded),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Transaction History',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (account.ledger.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 30),
                          child: Center(
                            child: Text('No credit movements yet.'),
                          ),
                        )
                      else
                        for (final entry in account.ledger) ...[
                          Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: entry.isPositive
                                    ? const Color(0xFFDCFCE7)
                                    : const Color(0xFFFEF3C7),
                                child: Icon(
                                  entry.isPositive ? Icons.add : Icons.remove,
                                  color: entry.isPositive
                                      ? const Color(0xFF166534)
                                      : const Color(0xFF92400E),
                                  size: 18,
                                ),
                              ),
                              title: Text(
                                entry.description ?? _formatType(entry.type),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Text(
                                '${entry.createdAt.toLocal().toString().split('.').first} · ${entry.type}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              trailing: Text(
                                '${entry.isPositive ? '+' : ''}${entry.amount}',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: entry.isPositive
                                      ? const Color(0xFF166534)
                                      : const Color(0xFF92400E),
                                  fontFamily: 'Trebuchet MS',
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      if (_loadMoreError != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'Could not load more transactions. $_loadMoreError',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      if (_nextCursor != null)
                        Center(
                          child: TextButton.icon(
                            onPressed: _loadingMore ? null : _loadMore,
                            icon: _loadingMore
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.expand_more_rounded),
                            label: Text(
                              _loadingMore
                                  ? 'Loading transactions'
                                  : 'Load more transactions',
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatType(String type) {
    switch (type) {
      case 'welcome':
        return 'Welcome Bonus';
      case 'listing_reward':
        return 'Legacy Listing Bonus';
      case 'reserved':
        return 'Legacy Exchange Hold';
      case 'earned':
        return 'Credits Earned';
      case 'refund':
        return 'Credit Refund';
      case 'spent':
        return 'Book Purchase';
      case 'credit_purchase':
        return 'Credit Purchase';
      default:
        return 'Credit Movement';
    }
  }

  Widget _summaryChip(String label, int amount) {
    return Chip(label: Text('$label  $amount'));
  }
}
