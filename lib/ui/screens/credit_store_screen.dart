import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../backend.dart';
import '../../models/library_models.dart';

class CreditStoreScreen extends StatefulWidget {
  const CreditStoreScreen({super.key});

  @override
  State<CreditStoreScreen> createState() => _CreditStoreScreenState();
}

class _CreditStoreScreenState extends State<CreditStoreScreen>
    with WidgetsBindingObserver {
  late Future<void> _loadFuture;
  final _transactionsKey = GlobalKey();
  CreditStoreCatalog? _catalog;
  CreditAccount? _account;
  List<CreditPurchase> _purchases = const [];
  String? _selectedPackageId;
  String? _pendingPurchaseId;
  String? _checkoutRequestId;
  Razorpay? _razorpay;
  bool _submitting = false;
  bool _walletRefreshFailedAfterConfirmation = false;
  final Set<String> _announcedCompletedPurchases = {};
  final Set<String> _refreshingPurchaseIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!kIsWeb) {
      final gateway = Razorpay();
      gateway.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
      gateway.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
      gateway.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
      _razorpay = gateway;
    }
    _loadFuture = _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _razorpay?.clear();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _pendingPurchaseId != null) {
      _refreshPurchaseStatus(_pendingPurchaseId!);
    }
  }

  Future<void> _load() async {
    final values = await Future.wait<Object>([
      MySqlApiService.instance.getCreditPackages(),
      MySqlApiService.instance.getCredits(),
      MySqlApiService.instance.getCreditPurchases(),
    ]);
    if (!mounted) return;
    setState(() {
      _catalog = values[0] as CreditStoreCatalog;
      _account = values[1] as CreditAccount;
      _purchases = values[2] as List<CreditPurchase>;
      if (_selectedPackageId == null && _catalog!.packages.isNotEmpty) {
        _selectedPackageId = _catalog!.packages
            .firstWhere(
              (item) => item.popular,
              orElse: () => _catalog!.packages.first,
            )
            .id;
      }
    });
  }

  Future<void> _refresh() async {
    setState(() => _loadFuture = _load());
    await _loadFuture;
    if (mounted && _walletRefreshFailedAfterConfirmation) {
      setState(() => _walletRefreshFailedAfterConfirmation = false);
    }
  }

  String _newIdempotencyKey() {
    return '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
  }

  Future<void> _buySelectedPackage() async {
    final package = _selectedPackage;
    final account = _account;
    if (package == null ||
        account == null ||
        _catalog?.paymentsEnabled != true ||
        kIsWeb) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm credit purchase'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("You're purchasing ${package.credits} Leaf & Lore Credits."),
            const SizedBox(height: 16),
            _confirmationLine(
              'Price',
              _formatAmount(package.amountMinor, package.currency),
            ),
            _confirmationLine('Available now', '${account.balance} credits'),
            _confirmationLine(
              'After verified payment',
              '${account.balance + package.credits} credits',
            ),
            const SizedBox(height: 12),
            Text(
              'Credits are added only after Razorpay confirms the payment with our backend.',
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.lock_outline_rounded, size: 18),
            label: const Text('Continue to Payment'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      _checkoutRequestId ??= _newIdempotencyKey();
      final result = await MySqlApiService.instance.createCreditPurchase(
        package.id,
        idempotencyKey: _checkoutRequestId!,
      );
      _checkoutRequestId = null;
      final purchaseId = result['id'] as String;
      if (result['status'] == 'completed') {
        await _refreshPurchaseStatus(purchaseId);
        return;
      }
      _pendingPurchaseId = purchaseId;
      _openRazorpayCheckout(
        purchaseId: purchaseId,
        orderId: result['order_id'] as String,
        keyId: result['key_id'] as String,
        amountMinor: (result['amount'] as num).toInt(),
        currency: result['currency'] as String,
        description: '${package.credits} Leaf & Lore Credits',
      );
      await _refresh();
    } catch (error) {
      if (!_cleanError(error).contains('Unable to reach')) {
        _checkoutRequestId = null;
      }
      _showMessage(_cleanError(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _showPhonePeQr() async {
    final package = _selectedPackage;
    if (package == null) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          title: const Text('PhonePe UPI QR'),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 360,
              maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.7,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${package.credits} credits · ${_formatAmount(package.amountMinor, package.currency)}',
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Image.asset(
                    'assets/phonepe_upi_qr.png',
                    width: 300,
                    fit: BoxFit.fitWidth,
                    semanticLabel: 'PhonePe UPI payment QR code',
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'This is a static personal UPI QR, not a gateway order. '
                      'Before paying, confirm PhonePe shows the intended '
                      'recipient and exactly ${_formatAmount(package.amountMinor, package.currency)}. '
                      'Cancel if they do not match. This app cannot verify '
                      'this transfer or automatically add credits.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _openRazorpayCheckout({
    required String purchaseId,
    required String orderId,
    required String keyId,
    required int amountMinor,
    required String currency,
    required String description,
  }) {
    final gateway = _razorpay;
    if (gateway == null) {
      _showMessage(
        'Razorpay Checkout is available in the Android and iOS app.',
      );
      return;
    }
    _pendingPurchaseId = purchaseId;
    gateway.open({
      'key': keyId,
      'order_id': orderId,
      'amount': amountMinor,
      'currency': currency,
      'name': 'Leaf & Lore',
      'description': description,
      'theme': {'color': '#1B3B2B'},
      'prefill': {
        if (MySqlApiService.instance.currentUser?.email != null)
          'email': MySqlApiService.instance.currentUser!.email,
      },
      'notes': {'purchase_id': purchaseId},
    });
  }

  Future<void> _handlePaymentSuccess(PaymentSuccessResponse response) async {
    final purchaseId = _pendingPurchaseId;
    final orderId = response.orderId;
    final paymentId = response.paymentId;
    final signature = response.signature;
    if (purchaseId == null ||
        orderId == null ||
        paymentId == null ||
        signature == null) {
      _showMessage(
        "Payment received. We're confirming your purchase with Razorpay...",
      );
      if (purchaseId != null) await _refreshPurchaseStatus(purchaseId);
      return;
    }
    try {
      await MySqlApiService.instance.verifyCreditPurchase(
        purchaseId: purchaseId,
        orderId: orderId,
        paymentId: paymentId,
        signature: signature,
      );
      await _refreshPurchaseStatus(purchaseId);
    } catch (_) {
      _showMessage(
        "Payment received. We're confirming your purchase with Razorpay...",
      );
      await _refreshPurchaseStatus(purchaseId);
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    _showMessage(
      response.message == null
          ? 'Payment attempt failed or was cancelled. No credits are added unless the backend verifies payment. You can check the saved purchase status.'
          : 'Payment attempt failed: ${response.message}. No credits are added unless the backend verifies payment. You can check the saved purchase status.',
    );
    final purchaseId = _pendingPurchaseId;
    if (purchaseId != null) _refreshPurchaseStatus(purchaseId);
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    _showMessage(
      'Complete the payment in ${response.walletName ?? 'the selected wallet'}, then return here.',
    );
  }

  Future<void> _resumeCheckout(CreditPurchase purchase) async {
    final orderId = purchase.paymentReference;
    final keyId = purchase.checkoutKeyId;
    if (orderId == null || keyId == null) return;
    _openRazorpayCheckout(
      purchaseId: purchase.id,
      orderId: orderId,
      keyId: keyId,
      amountMinor: purchase.amountMinor,
      currency: purchase.currency,
      description: '${purchase.credits} Leaf & Lore Credits',
    );
  }

  Future<void> _refreshPurchaseStatus(String purchaseId) async {
    if (!_refreshingPurchaseIds.add(purchaseId)) return;
    try {
      final purchase = await MySqlApiService.instance.getCreditPurchase(
        purchaseId,
      );
      if (!mounted) return;
      try {
        await _refresh();
      } catch (_) {
        if (purchase.status == 'completed' && mounted) {
          setState(() => _walletRefreshFailedAfterConfirmation = true);
          _showMessage(
            'Payment is confirmed by the backend, but wallet refresh failed. Tap “Refresh wallet” to retry safely.',
          );
        } else if (mounted) {
          _showMessage(
            'Purchase status was checked, but wallet data could not be refreshed. Tap “Refresh wallet” to retry.',
          );
        }
        return;
      }
      if (!mounted) return;
      if (purchase.status == 'cancelled') {
        _pendingPurchaseId = null;
        _showMessage('Payment was cancelled. No credits were added.');
        return;
      }
      if (purchase.status == 'failed') {
        _pendingPurchaseId = null;
        _showMessage('Payment could not be verified. No credits were added.');
        return;
      }
      if (purchase.status != 'completed') return;
      _pendingPurchaseId = null;
      if (!_announcedCompletedPurchases.add(purchaseId)) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.check_circle_outline_rounded, size: 38),
          title: const Text('Credits Added'),
          content: Text(
            '+${purchase.credits} Credits\nNew balance: ${_account?.balance ?? 0} Credits\nPurchase completed successfully.',
            textAlign: TextAlign.center,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                SchedulerBinding.instance.addPostFrameCallback((_) {
                  final target = _transactionsKey.currentContext;
                  if (target != null) Scrollable.ensureVisible(target);
                });
              },
              child: const Text('View Transaction'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                Navigator.pop(context);
              },
              child: const Text('View Wallet'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        _showMessage('Unable to refresh payment status. Please try again.');
      }
    } finally {
      _refreshingPurchaseIds.remove(purchaseId);
    }
  }

  CreditPackage? get _selectedPackage {
    final packages = _catalog?.packages ?? const <CreditPackage>[];
    for (final package in packages) {
      if (package.id == _selectedPackageId) return package;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Credit Store'),
        actions: [
          IconButton(
            tooltip: 'Refresh wallet',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              _account == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError && _account == null) {
            return _loadError(theme, snapshot.error);
          }
          final catalog = _catalog;
          final account = _account;
          if (catalog == null || account == null) {
            return const SizedBox.shrink();
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 32),
              children: [
                _balanceCard(theme, account),
                if (_walletRefreshFailedAfterConfirmation) ...[
                  const SizedBox(height: 12),
                  _confirmedRefreshNotice(theme),
                ],
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Choose a package',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => Scrollable.ensureVisible(
                        _transactionsKey.currentContext ?? context,
                        duration: const Duration(milliseconds: 250),
                      ),
                      icon: const Icon(Icons.receipt_long_rounded, size: 18),
                      label: const Text('History'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (catalog.packages.isEmpty)
                  const Text('No credit packages are currently available.')
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 720 ? 4 : 2;
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: catalog.packages.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          mainAxisExtent: 184,
                        ),
                        itemBuilder: (context, index) =>
                            _packageCard(theme, catalog.packages[index]),
                      );
                    },
                  ),
                if (!catalog.paymentsEnabled) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded, size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Payments are currently unavailable. Razorpay TEST MODE configuration is required; no credits will be charged or added.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed:
                      catalog.paymentsEnabled &&
                          !kIsWeb &&
                          !_submitting &&
                          _selectedPackage != null
                      ? _buySelectedPackage
                      : null,
                  icon: _submitting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lock_outline_rounded),
                  label: Text(
                    _submitting
                        ? 'Preparing secure checkout'
                        : 'Continue to Payment',
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _selectedPackage == null ? null : _showPhonePeQr,
                  icon: const Icon(Icons.qr_code_2_rounded),
                  label: const Text('View PhonePe QR (manual payment)'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
                const SizedBox(height: 28),
                _summarySection(theme, account.summary),
                const SizedBox(height: 26),
                _purchaseHistory(theme),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _balanceCard(ThemeData theme, CreditAccount account) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.auto_stories_rounded,
            color: Color(0xFFFFD98A),
            size: 36,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Available Credits',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${account.balance}',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const Text(
            'LL',
            style: TextStyle(
              color: Color(0xFFFFD98A),
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _packageCard(ThemeData theme, CreditPackage package) {
    final selected = package.id == _selectedPackageId;
    return InkWell(
      onTap: () => setState(() => _selectedPackageId = package.id),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? theme.colorScheme.primary : theme.dividerColor,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    package.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (package.popular)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD09B42).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Popular',
                      style: TextStyle(
                        color: Color(0xFF966A1D),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Text(
              '${package.credits}',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text('Credits', style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Text(
              _formatAmount(package.amountMinor, package.currency),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '${_formatAmount((package.amountMinor * 100) ~/ package.credits, package.currency)} per 100',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _summarySection(ThemeData theme, CreditSummary summary) {
    final values = [
      ('Earned', summary.earned, Icons.trending_up_rounded),
      ('Purchased', summary.purchased, Icons.add_card_rounded),
      ('Spent', summary.spent, Icons.shopping_bag_outlined),
      ('Held', summary.held, Icons.lock_clock_outlined),
      ('Refunded', summary.refunded, Icons.undo_rounded),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Credit activity', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final item in values)
              SizedBox(
                width: 150,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.55,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(item.$3, size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(item.$1, style: theme.textTheme.bodySmall),
                      ),
                      Text(
                        '${item.$2}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _purchaseHistory(ThemeData theme) {
    return Column(
      key: _transactionsKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Credit Purchase History', style: theme.textTheme.titleLarge),
        const SizedBox(height: 10),
        if (_purchases.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.45,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'No credit purchases yet. Your verified Razorpay purchases will appear here.',
            ),
          )
        else
          for (final purchase in _purchases)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.receipt_long_rounded),
                ),
                title: Text(
                  '${purchase.credits} Credits · ${purchase.packageName}',
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${purchase.createdAt.toLocal().toString().split('.').first} · ${purchase.status.toUpperCase()}\n${purchase.paymentReference == null ? 'Order ${purchase.id}' : 'Ref ${purchase.paymentReference}'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (purchase.paymentProvider == 'razorpay' &&
                        purchase.paymentReference != null &&
                        purchase.checkoutKeyId != null &&
                        purchase.status == 'processing')
                      TextButton.icon(
                        onPressed: () => _resumeCheckout(purchase),
                        icon: const Icon(Icons.open_in_new_rounded, size: 16),
                        label: const Text('Resume checkout'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                    if (purchase.status == 'processing' ||
                        purchase.status == 'pending')
                      TextButton.icon(
                        onPressed: _refreshingPurchaseIds.contains(purchase.id)
                            ? null
                            : () => _refreshPurchaseStatus(purchase.id),
                        icon: const Icon(Icons.sync_rounded, size: 16),
                        label: Text(
                          _refreshingPurchaseIds.contains(purchase.id)
                              ? 'Checking status'
                              : 'Check purchase status',
                        ),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                  ],
                ),
                trailing: Text(
                  _formatAmount(purchase.amountMinor, purchase.currency),
                ),
              ),
            ),
      ],
    );
  }

  Widget _loadError(ThemeData theme, Object? error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 38),
            const SizedBox(height: 12),
            Text(
              'Wallet data could not be loaded. ${_cleanError(error)}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _confirmedRefreshNotice(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.verified_outlined,
            color: theme.colorScheme.onTertiaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'The server confirmed your payment. Wallet data still needs a refresh.',
              style: TextStyle(color: theme.colorScheme.onTertiaryContainer),
            ),
          ),
          TextButton(onPressed: _refresh, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _confirmationLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  String _formatAmount(int amountMinor, String currency) {
    const zeroFractionCurrencies = {
      'BIF',
      'CLP',
      'DJF',
      'GNF',
      'ISK',
      'JPY',
      'KMF',
      'KRW',
      'PYG',
      'RWF',
      'UGX',
      'VND',
      'VUV',
      'XAF',
      'XOF',
      'XPF',
    };
    const threeFractionCurrencies = {
      'BHD',
      'IQD',
      'JOD',
      'KWD',
      'LYD',
      'OMR',
      'TND',
    };
    final normalizedCurrency = currency.toUpperCase();
    final fractionDigits = zeroFractionCurrencies.contains(normalizedCurrency)
        ? 0
        : threeFractionCurrencies.contains(normalizedCurrency)
        ? 3
        : 2;
    final amount = amountMinor / pow(10, fractionDigits);
    final value = amount == amount.roundToDouble()
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(fractionDigits);
    return normalizedCurrency == 'INR' ? '₹$value' : '$currency $value';
  }

  String _cleanError(Object? error) {
    return error.toString().replaceFirst('Exception: ', '');
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
