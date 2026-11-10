import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:book_exchange_app/backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'expired restored session is cleared after an unauthorized response',
    () async {
      SharedPreferences.setMockInitialValues({
        'leaf_lore_session_token': 'expired-session-token',
        'leaf_lore_user_id': 'user-1',
        'leaf_lore_user_name': 'Reader',
        'leaf_lore_user_email': 'reader@example.com',
      });
      final service = MySqlApiService.testing(
        MockClient(
          (_) async => http.Response(
            jsonEncode({'message': 'Authentication required. Please sign in.'}),
            401,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );

      await service.restoreSession();
      expect(service.isAuthenticated, isTrue);

      await service.validateRestoredSession();

      expect(service.isAuthenticated, isFalse);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('leaf_lore_session_token'), isNull);
      expect(preferences.getString('leaf_lore_user_id'), isNull);
    },
  );

  test('credit account accepts numeric values serialized as strings', () async {
    final service = MySqlApiService.testing(
      MockClient(
        (_) async => http.Response(
          jsonEncode({
            'balance': '10',
            'ledger': [],
            'summary': {
              'earned': '10',
              'purchased': '0',
              'spent': '0',
              'held': '0',
              'refunded': '0',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );

    final account = await service.getCredits();

    expect(account.balance, 10);
    expect(account.summary.earned, 10);
    expect(account.summary.purchased, 0);
    expect(account.summary.spent, 0);
    expect(account.summary.held, 0);
    expect(account.summary.refunded, 0);
  });

  test(
    'restored session remains available when the server rejects another request',
    () async {
      SharedPreferences.setMockInitialValues({
        'leaf_lore_session_token': 'session-token',
        'leaf_lore_user_id': 'user-1',
        'leaf_lore_user_name': 'Reader',
        'leaf_lore_user_email': 'reader@example.com',
      });
      final service = MySqlApiService.testing(
        MockClient(
          (_) async => http.Response(
            jsonEncode({'message': 'Server unavailable.'}),
            503,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );

      await service.restoreSession();
      await expectLater(
        service.validateRestoredSession(),
        throwsA(isA<ApiRequestException>()),
      );

      expect(service.isAuthenticated, isTrue);
    },
  );
}
