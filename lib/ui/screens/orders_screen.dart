import 'dart:async';

import 'package:flutter/material.dart';
import '../../backend.dart';
import '../../models/library_models.dart';
import '../widgets/book_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/status_badge.dart';
import 'review_dialog.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  Timer? _refreshTimer;
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;
  List<MarketplaceOrder> _orders = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadOrders();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _loadOrders(showLoading: false),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadOrders({bool showLoading = true}) async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    if (showLoading && mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    try {
      final orders = await MySqlApiService.instance.getMarketplaceOrders();
      if (mounted) {
        setState(() {
          _orders = orders;
          _isLoading = false;
          _errorMessage = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = error.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      _isRefreshing = false;
    }
  }

  Future<void> _addShippingDetails(MarketplaceOrder order) async {
    final formKey = GlobalKey<FormState>();
    final carrierController = TextEditingController();
    final trackingController = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add shipping details'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: carrierController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Carrier',
                  hintText: 'e.g. India Post',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter the carrier'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: trackingController,
                decoration: const InputDecoration(labelText: 'Tracking number'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter the tracking number'
                    : null,
              ),
            ],
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
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (submitted != true || !mounted) {
      carrierController.dispose();
      trackingController.dispose();
      return;
    }

    try {
      await MySqlApiService.instance.updateMarketplaceShipping(
        orderId: order.id,
        carrier: carrierController.text.trim(),
        trackingNumber: trackingController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Shipping details saved.')),
        );
        await _loadOrders();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      carrierController.dispose();
      trackingController.dispose();
    }
  }

  Future<void> _confirmDelivery(MarketplaceOrder order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm delivery'),
        content: Text('Have you received "${order.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Yes, received'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await MySqlApiService.instance.confirmMarketplaceDelivery(order.id);
      if (mounted) await _loadOrders();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    }
  }

  List<MarketplaceOrder> _ordersForTab(int index) {
    return switch (index) {
      0 =>
        _orders.where((order) => order.isBuyer && !order.isDelivered).toList(),
      1 =>
        _orders.where((order) => order.isSeller && !order.isDelivered).toList(),
      _ => _orders.where((order) => order.isDelivered).toList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final pendingPurchases = _orders
        .where((order) => order.isBuyer && !order.isDelivered)
        .length;
    final pendingSales = _orders
        .where((order) => order.isSeller && !order.isDelivered)
        .length;
    final delivered = _orders.where((order) => order.isDelivered).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Purchases ($pendingPurchases)'),
            Tab(text: 'Sales ($pendingSales)'),
            Tab(text: 'History ($delivered)'),
          ],
        ),
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
                    Text(_errorMessage!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _loadOrders,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: List.generate(3, (index) {
                final orders = _ordersForTab(index);
                return RefreshIndicator(
                  onRefresh: _loadOrders,
                  child: orders.isEmpty
                      ? ListView(
                          children: [
                            SizedBox(
                              height: MediaQuery.sizeOf(context).height * 0.18,
                            ),
                            EmptyStateWidget(
                              icon: index == 2
                                  ? Icons.inventory_2_outlined
                                  : Icons.local_shipping_outlined,
                              title: index == 0
                                  ? 'No purchases yet'
                                  : index == 1
                                  ? 'No books to ship'
                                  : 'No delivered orders yet',
                              subtitle: index == 0
                                  ? 'Books you buy with credits will appear here.'
                                  : index == 1
                                  ? 'Orders for books you sell will appear here.'
                                  : 'Completed deliveries will be kept here.',
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: orders.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, orderIndex) =>
                              _orderCard(orders[orderIndex]),
                        ),
                );
              }),
            ),
    );
  }

  Widget _orderCard(MarketplaceOrder order) {
    final theme = Theme.of(context);
    final address = [
      order.recipientName,
      order.addressLine1,
      if (order.addressLine2?.isNotEmpty == true) order.addressLine2!,
      '${order.city}, ${order.region} ${order.postalCode}',
      order.country,
      order.recipientPhone,
    ].join('\n');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BookCoverWidget(
                  title: order.title,
                  coverUrl: order.coverImageUrl,
                  width: 56,
                  height: 78,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StatusBadge(status: order.status),
                      const SizedBox(height: 6),
                      Text(
                        order.title,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (order.author.isNotEmpty)
                        Text(
                          'by ${order.author}',
                          style: theme.textTheme.bodySmall,
                        ),
                      const SizedBox(height: 6),
                      Text(
                        '${order.credits} credits',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (order.isSeller && !order.isDelivered) ...[
              const Divider(height: 24),
              Text('Ship to', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              Text(address, style: theme.textTheme.bodyMedium),
            ],
            if (order.isShipped) ...[
              const Divider(height: 24),
              Text(
                'Shipping: ${order.shippingCarrier ?? 'Carrier not provided'}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (order.trackingNumber?.isNotEmpty == true)
                SelectableText('Tracking: ${order.trackingNumber}'),
            ],
            if (order.isSeller && order.isPaid) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _addShippingDetails(order),
                  icon: const Icon(Icons.local_shipping_outlined),
                  label: const Text('Mark as shipped'),
                ),
              ),
            ],
            if (order.isBuyer && order.isShipped) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _confirmDelivery(order),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Confirm delivery'),
                ),
              ),
            ],
            if (order.canReview) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () async {
                    final submitted = await ReviewDialog.show(
                      context,
                      exchangeId: order.id,
                      bookTitle: order.title,
                      partnerName: order.otherPartyName,
                    );
                    if (submitted == true && mounted) await _loadOrders();
                  },
                  icon: const Icon(Icons.star_outline_rounded),
                  label: const Text('Review this order'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
