import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:book_exchange_app/backend.dart';
import 'package:book_exchange_app/models/catalog_book.dart';
import 'package:book_exchange_app/ui/screens/catalog_book_purchase_screen.dart';
import 'package:book_exchange_app/ui/widgets/book_catalog_shelf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const book = CatalogBook(
    key: '/works/silent-patient',
    title: 'The Silent Patient',
    author: 'Alex Michaelides',
    coverUrl: '',
  );

  testWidgets('catalog purchase finds real credit-priced seller listings', (
    tester,
  ) async {
    Uri? requestedUri;
    final service = MySqlApiService.testing(
      MockClient((request) async {
        requestedUri = request.url;
        return http.Response(
          jsonEncode({
            'listings': [
              {
                'id': 'listing-1',
                'owner_id': 'seller-1',
                'title': 'The Silent Patient',
                'author': 'Alex Michaelides',
                'category': 'Mystery',
                'book_condition': 'Good',
                'description': 'Paperback copy',
                'credit_value': 12,
                'status': 'available',
                'created_at': '2026-10-31 10:00:00',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CatalogBookPurchaseScreen(book: book, service: service),
      ),
    );
    await tester.pumpAndSettle();

    expect(requestedUri?.queryParameters['q'], book.title);
    expect(requestedUri?.queryParameters['status'], 'available');
    expect(find.text('Available copies (1)'), findsOneWidget);
    expect(find.text('The Silent Patient'), findsWidgets);
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets(
    'unlisted catalog books offer a community request, not fake stock',
    (tester) async {
      final service = MySqlApiService.testing(
        MockClient(
          (_) async => http.Response(
            jsonEncode({'listings': []}),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: CatalogBookPurchaseScreen(book: book, service: service),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No copies listed yet'), findsWidgets);
      expect(find.text('Request this book'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Check again'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Check again'), findsOneWidget);
    },
  );

  testWidgets('popular book cards open the credit purchase listing flow', (
    tester,
  ) async {
    final service = MySqlApiService.testing(
      MockClient((request) async {
        if (request.url.path.endsWith('/api/book-catalog')) {
          return http.Response(
            jsonEncode({
              'books': [
                {
                  'key': book.key,
                  'title': book.title,
                  'author': book.author,
                  'cover_url': book.coverUrl,
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({'listings': []}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await tester.pumpWidget(
      MaterialApp(home: BookCatalogShelf(service: service)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Buy with credits'));
    await tester.pumpAndSettle();

    expect(find.text('Available copies (0)'), findsOneWidget);
    expect(find.text('Request this book'), findsOneWidget);
  });
}
