import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:book_exchange_app/backend.dart';
import 'package:book_exchange_app/models/catalog_book.dart';
import 'package:book_exchange_app/models/library_models.dart';
import 'package:book_exchange_app/ui/app_shell.dart';
import 'package:book_exchange_app/ui/screens/discover_screen.dart';
import 'package:book_exchange_app/ui/screens/demo_showcase_screen.dart';
import 'package:book_exchange_app/ui/screens/list_book_screen.dart';
import 'package:book_exchange_app/ui/screens/ledger_sheet.dart';
import 'package:book_exchange_app/ui/screens/orders_screen.dart';
import 'package:book_exchange_app/ui/widgets/book_card.dart';
import 'package:book_exchange_app/ui/widgets/status_badge.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Leaf & Lore app launches into authentic login screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const LeafAndLoreApp());
    await tester.pumpAndSettle();

    expect(find.text('Leaf & Lore'), findsWidgets);
    expect(find.text('Books found.\nStories shared.'), findsOneWidget);
    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('New to Leaf & Lore? Create Account'), findsOneWidget);

    // Switch to Registration mode
    await tester.ensureVisible(find.text('New to Leaf & Lore? Create Account'));
    await tester.tap(find.text('New to Leaf & Lore? Create Account'));
    await tester.pumpAndSettle();

    expect(find.text('Join the Community'), findsOneWidget);
    expect(find.text('Full Name'), findsOneWidget);
    expect(find.text('Create Account & Get 15 Credits'), findsOneWidget);

    // Validate inputs
    await tester.ensureVisible(find.text('Create Account & Get 15 Credits'));
    await tester.tap(find.text('Create Account & Get 15 Credits'));
    await tester.pumpAndSettle();

    expect(find.text('Enter your name'), findsOneWidget);
    expect(find.text('Enter a valid email'), findsOneWidget);
  });

  testWidgets('offline showcase runs with sample content and navigation', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: DemoShowcaseScreen(onExit: () {})),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'OFFLINE DEMO  ·  Sample books and activity only; no real orders or payments',
      ),
      findsOneWidget,
    );
    expect(find.text('Popular books'), findsOneWidget);
    expect(find.text('The Hobbit'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Discover').last);
    await tester.pumpAndSettle();
    expect(find.text('Search title, author, genre...'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Atomic Habits');
    await tester.pumpAndSettle();
    expect(find.text('Atomic Habits'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login can open the offline showcase without backend access', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const LeafAndLoreApp());
    await tester.pumpAndSettle();

    expect(find.text('Sign In'), findsOneWidget);
    await tester.ensureVisible(find.text('Explore offline demo'));
    await tester.tap(find.text('Explore offline demo'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'OFFLINE DEMO  ·  Sample books and activity only; no real orders or payments',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('MainAppShell displays 5 core navigation tabs', (
    WidgetTester tester,
  ) async {
    MySqlApiService.instance.currentUser = const ApiUser(
      id: 'test-user-1',
      name: 'Eleanor Vance',
      email: 'eleanor@example.com',
      location: 'Greenwich Guild',
    );

    await tester.pumpWidget(const MaterialApp(home: MainAppShell()));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Discover'), findsOneWidget);
    expect(find.text('Orders'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
  });

  testWidgets('DiscoverScreen renders search input and category chips', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: DiscoverScreen()));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Fiction'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ListBookScreen fits a narrow phone viewport', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: ListBookScreen()));
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('OrdersScreen renders marketplace order tabs', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: OrdersScreen()));
    await tester.pump();

    expect(find.byType(TabBar), findsOneWidget);
    expect(find.textContaining('Purchases'), findsOneWidget);
    expect(find.textContaining('Sales'), findsOneWidget);
    expect(find.textContaining('History'), findsOneWidget);
  });

  testWidgets('StatusBadge renders appropriate labels and colors', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              StatusBadge(status: 'paid'),
              StatusBadge(status: 'shipped'),
              StatusBadge(status: 'delivered'),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Paid · awaiting shipment'), findsOneWidget);
    expect(find.text('Shipped'), findsOneWidget);
    expect(find.text('Delivered'), findsOneWidget);
  });

  testWidgets('ListingCard displays credit value, condition, and title', (
    WidgetTester tester,
  ) async {
    final listing = MarketplaceListing(
      id: 'test-listing-1',
      ownerId: 'owner-1',
      title: 'The Great Gatsby',
      author: 'F. Scott Fitzgerald',
      category: 'Classics',
      bookCondition: 'Like New',
      description: 'First edition reprint.',
      creditValue: 12,
      status: 'available',
      createdAt: DateTime.now(),
      ownerName: 'Clara Oswald',
      ownerLocation: 'Mayfair',
      ownerRating: 4.9,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListingCard(listing: listing, onTap: () {}),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('The Great Gatsby'), findsNWidgets(2));
    expect(find.text('F. Scott Fitzgerald'), findsOneWidget);
    expect(find.text('Like New'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('Clara Oswald'), findsOneWidget);
  });

  testWidgets('ListingCard metadata wraps on a narrow phone viewport', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final listing = MarketplaceListing(
      id: 'narrow-test-listing',
      ownerId: 'owner-1',
      title: 'The Great Gatsby',
      author: 'F. Scott Fitzgerald',
      category: 'Non-fiction',
      bookCondition: 'Very Good',
      description: 'First edition reprint.',
      creditValue: 12,
      status: 'available',
      createdAt: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [ListingCard(listing: listing, onTap: () {})],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  test('Credit package and wallet summary parse backend values', () {
    final package = CreditPackage.fromMap({
      'id': 'popular',
      'name': 'Popular',
      'credits': 250,
      'amount_minor': 9900,
      'currency': 'INR',
      'popular': true,
    });

    final summary = CreditSummary.fromMap({
      'earned': 17,
      'purchased': 250,
      'spent': 10,
      'held': 5,
      'refunded': 3,
    });

    expect(package.credits, 250);
    expect(package.amountMinor, 9900);
    expect(package.popular, isTrue);
    expect(summary.earned, 17);
    expect(summary.purchased, 250);
    expect(summary.spent, 10);
    expect(summary.held, 5);
    expect(summary.refunded, 3);
  });

  test('featured catalog books parse cover and attribution data', () {
    final book = CatalogBook.fromMap({
      'key': '/works/OL19096402W',
      'title': 'The Silent Patient',
      'author': 'Alex Michaelides',
      'cover_url': 'https://covers.openlibrary.org/b/id/9407338-L.jpg',
      'first_publish_year': 2018,
    });

    expect(book.title, 'The Silent Patient');
    expect(book.author, 'Alex Michaelides');
    expect(book.coverUrl, contains('9407338'));
    expect(book.firstPublishYear, 2018);
  });

  test('PhonePe QR image is bundled as a Flutter asset', () async {
    final image = await rootBundle.load('assets/phonepe_upi_qr.png');
    expect(image.lengthInBytes, greaterThan(100000));
  });

  test('new profiles do not display fabricated balances or ratings', () {
    final profile = UserProfile.fromMap({
      'id': 'new-reader',
      'display_name': 'New Reader',
      'email': 'reader@example.com',
      'location': '',
      'bio': '',
      'role': 'member',
    });

    expect(profile.credits, 0);
    expect(profile.rating, isNull);
    expect(profile.reviewCount, 0);
  });

  test('new listing owners do not receive a fabricated trust rating', () {
    final listing = MarketplaceListing.fromMap({
      'id': 'new-listing',
      'owner_id': 'new-reader',
      'title': 'A New Book',
      'author': 'A New Author',
      'owner_rating': null,
    });

    expect(listing.ownerRating, isNull);
  });

  testWidgets(
    'Credit ledger displays server pages and loads older transactions',
    (WidgetTester tester) async {
      var requests = 0;
      String? requestedCursor;
      final client = MockClient((request) async {
        requests++;
        requestedCursor = request.url.queryParameters['cursor'];
        final isNextPage = request.url.queryParameters.containsKey('cursor');
        final entry = isNextPage
            ? {
                'id': 'ledger-older',
                'amount': -4,
                'type': 'reserved',
                'description': 'Older exchange hold',
                'created_at': '2026-10-01 10:00:00',
              }
            : {
                'id': 'ledger-newer',
                'amount': 15,
                'type': 'welcome',
                'description': 'Welcome credits',
                'created_at': '2026-10-02 10:00:00',
              };
        return http.Response(
          jsonEncode({
            'balance': 11,
            'ledger': [entry],
            'summary': {'earned': 15, 'held': 4},
            'has_more': !isNextPage,
            'next_cursor': isNextPage ? null : 'next-page-cursor',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = MySqlApiService.testing(client);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CreditLedgerSheet(service: service)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('11 Credits'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -900));
      await tester.pumpAndSettle();

      expect(find.text('Welcome credits'), findsOneWidget);
      final loadMore = find.text('Load more transactions');
      await tester.tap(loadMore);
      await tester.pumpAndSettle();

      expect(requests, 2);
      expect(requestedCursor, 'next-page-cursor');
      await tester.scrollUntilVisible(
        find.text('Older exchange hold'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Older exchange hold'), findsOneWidget);
      expect(find.text('Load more transactions'), findsNothing);
    },
  );

  testWidgets('Credit ledger shows retryable server errors', (
    WidgetTester tester,
  ) async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response(
        jsonEncode({'message': 'Wallet is temporarily unavailable.'}),
        503,
        headers: {'content-type': 'application/json'},
      );
    });
    final service = MySqlApiService.testing(client);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CreditLedgerSheet(service: service)),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Wallet is temporarily unavailable.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(requests, 2);
  });

  test('Credit purchase parses verified status and provider reference', () {
    final purchase = CreditPurchase.fromMap({
      'id': 'purchase-1',
      'package_id': 'popular',
      'package_name': 'Popular',
      'credits': 250,
      'amount_minor': 9900,
      'currency': 'INR',
      'payment_provider': 'razorpay',
      'payment_reference': 'order_test_1',
      'checkout_key_id': 'rzp_test_public_key',
      'status': 'processing',
      'created_at': '2026-10-06T12:00:00',
    });

    expect(purchase.status, 'processing');
    expect(purchase.paymentReference, 'order_test_1');
    expect(purchase.checkoutKeyId, 'rzp_test_public_key');
    expect(purchase.completedAt, isNull);
  });
}
