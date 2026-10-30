import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models/catalog_book.dart';
import 'models/library_models.dart';

class BackendConfig {
  const BackendConfig._();

  static const _envApiUrl = String.fromEnvironment('API_BASE_URL');

  // Match the local launcher, which avoids common port-8080 conflicts.
  static String get apiUrl =>
      _envApiUrl.isNotEmpty ? _envApiUrl : 'http://127.0.0.1:8081';

  static bool get isApiConfigured => true;
}

class ApiUser {
  const ApiUser({
    required this.id,
    required this.name,
    required this.email,
    this.location,
    this.role = 'member',
  });

  final String id;
  final String name;
  final String email;
  final String? location;
  final String role;
}

class ApiAuthResponse {
  const ApiAuthResponse({required this.user, required this.token});

  final ApiUser user;
  final String token;
}

class MySqlApiService {
  MySqlApiService._() : _client = http.Client();

  MySqlApiService.testing(http.Client client) : _client = client;

  static final instance = MySqlApiService._();
  final http.Client _client;
  ApiUser? currentUser;
  String? _token;

  static const _tokenKey = 'leaf_lore_session_token';
  static const _userIdKey = 'leaf_lore_user_id';
  static const _userNameKey = 'leaf_lore_user_name';
  static const _userEmailKey = 'leaf_lore_user_email';
  static const _userLocationKey = 'leaf_lore_user_location';

  bool get isAuthenticated => _token != null && currentUser != null;

  Uri _uri(String path, [Map<String, String>? queryParams]) {
    final base = BackendConfig.apiUrl;
    final urlStr = base.endsWith('/')
        ? '${base.substring(0, base.length - 1)}$path'
        : '$base$path';
    return Uri.parse(urlStr).replace(queryParameters: queryParams);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParams,
    Map<String, String>? extraHeaders,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    if (extraHeaders != null) headers.addAll(extraHeaders);

    final uri = _uri(path, queryParams);
    http.Response response;

    try {
      if (method == 'GET') {
        response = await _client.get(uri, headers: headers);
      } else if (method == 'POST') {
        response = await _client.post(
          uri,
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        );
      } else if (method == 'PUT') {
        response = await _client.put(
          uri,
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        );
      } else if (method == 'DELETE') {
        response = await _client.delete(
          uri,
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        );
      } else {
        throw Exception('Unsupported HTTP method: $method');
      }
    } catch (e) {
      throw Exception(
        'Unable to reach Leaf & Lore server. Please ensure the backend is running.',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      decoded = {'message': 'Invalid server response: ${response.statusCode}'};
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final msg = decoded is Map && decoded['message'] != null
          ? decoded['message']
          : 'Server error (${response.statusCode})';
      throw Exception(msg);
    }

    return Map<String, dynamic>.from(decoded as Map);
  }

  Future<void> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    final id = prefs.getString(_userIdKey);
    final name = prefs.getString(_userNameKey);
    final email = prefs.getString(_userEmailKey);
    final location = prefs.getString(_userLocationKey);

    if (token == null || id == null || name == null || email == null) return;
    _token = token;
    currentUser = ApiUser(id: id, name: name, email: email, location: location);
  }

  Future<void> _persistSession(String token, ApiUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString(_tokenKey, token),
      prefs.setString(_userIdKey, user.id),
      prefs.setString(_userNameKey, user.name),
      prefs.setString(_userEmailKey, user.email),
      if (user.location != null)
        prefs.setString(_userLocationKey, user.location!),
    ]);
  }

  Future<ApiAuthResponse> register({
    required String name,
    required String email,
    required String password,
    String? location,
  }) async {
    final result = await _request(
      'POST',
      '/api/auth/register',
      body: {
        'name': name.trim(),
        'email': email.trim().toLowerCase(),
        'password': password,
        'location': location?.trim() ?? 'Local Community',
      },
    );

    final token = result['token'] as String;
    final userMap = Map<String, dynamic>.from(result['user'] as Map);
    final user = ApiUser(
      id: userMap['id'] as String,
      name: userMap['name'] as String,
      email: userMap['email'] as String,
      location: userMap['location'] as String?,
    );

    _token = token;
    currentUser = user;
    await _persistSession(token, user);
    return ApiAuthResponse(user: user, token: token);
  }

  Future<ApiAuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    final result = await _request(
      'POST',
      '/api/auth/login',
      body: {'email': email.trim().toLowerCase(), 'password': password},
    );

    final token = result['token'] as String;
    final userMap = Map<String, dynamic>.from(result['user'] as Map);
    final user = ApiUser(
      id: userMap['id'] as String,
      name: userMap['name'] as String,
      email: userMap['email'] as String,
      location: userMap['location'] as String?,
      role: userMap['role'] as String? ?? 'member',
    );

    _token = token;
    currentUser = user;
    await _persistSession(token, user);
    return ApiAuthResponse(user: user, token: token);
  }

  Future<void> signOut() async {
    Object? requestError;
    if (_token != null) {
      try {
        await _request('POST', '/api/auth/logout');
      } catch (error) {
        requestError = error;
      }
    }

    _token = null;
    currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_tokenKey),
      prefs.remove(_userIdKey),
      prefs.remove(_userNameKey),
      prefs.remove(_userEmailKey),
      prefs.remove(_userLocationKey),
    ]);
    if (requestError != null) {
      throw Exception(
        'Signed out on this device, but the server could not revoke the session: $requestError',
      );
    }
  }

  // User Profile
  Future<UserProfile> getProfile() async {
    final result = await _request('GET', '/api/profile');
    return UserProfile.fromMap(
      Map<String, dynamic>.from(result['profile'] as Map),
    );
  }

  Future<void> updateProfile({
    required String name,
    String? location,
    String? bio,
  }) async {
    await _request(
      'POST',
      '/api/profile',
      body: {
        'name': name.trim(),
        'location': location?.trim() ?? '',
        'bio': bio?.trim() ?? '',
      },
    );
    if (currentUser != null) {
      currentUser = ApiUser(
        id: currentUser!.id,
        name: name.trim(),
        email: currentUser!.email,
        location: location?.trim(),
        role: currentUser!.role,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userNameKey, name.trim());
      if (location != null) {
        await prefs.setString(_userLocationKey, location.trim());
      }
    }
  }

  Future<Map<String, dynamic>> getUserPublicProfile(String userId) async {
    final result = await _request('GET', '/api/users/$userId');
    return Map<String, dynamic>.from(result['profile'] as Map);
  }

  // Credit Account
  Future<CreditAccount> getCredits({String? cursor, int limit = 50}) async {
    final query = <String, String>{'limit': '$limit'};
    if (cursor != null) query['cursor'] = cursor;
    final result = await _request('GET', '/api/credits', queryParams: query);
    final balance = (result['balance'] as num?)?.toInt() ?? 0;
    final rawLedger = result['ledger'] as List? ?? [];
    final ledger = rawLedger
        .map(
          (e) => CreditLedgerEntry.fromMap(Map<String, dynamic>.from(e as Map)),
        )
        .toList(growable: false);
    final summary = CreditSummary.fromMap(
      result['summary'] is Map
          ? Map<String, dynamic>.from(result['summary'] as Map)
          : null,
    );
    return CreditAccount(
      balance: balance,
      ledger: ledger,
      summary: summary,
      hasMore: result['has_more'] == true,
      nextCursor: result['next_cursor'] as String?,
    );
  }

  Future<CreditStoreCatalog> getCreditPackages() async {
    final result = await _request('GET', '/api/credit-packages');
    final packages = (result['packages'] as List? ?? [])
        .map(
          (item) =>
              CreditPackage.fromMap(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
    return CreditStoreCatalog(
      packages: packages,
      paymentsEnabled: result['payments_enabled'] == true,
    );
  }

  Future<List<CreditPurchase>> getCreditPurchases() async {
    final result = await _request('GET', '/api/credit-purchases');
    return (result['purchases'] as List? ?? [])
        .map(
          (item) =>
              CreditPurchase.fromMap(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  }

  Future<CreditPurchase> getCreditPurchase(String purchaseId) async {
    final result = await _request('GET', '/api/credit-purchases/$purchaseId');
    return CreditPurchase.fromMap(
      Map<String, dynamic>.from(result['purchase'] as Map),
    );
  }

  Future<Map<String, dynamic>> createCreditPurchase(
    String packageId, {
    required String idempotencyKey,
  }) async {
    return _request(
      'POST',
      '/api/credit-purchases',
      body: {'package_id': packageId},
      extraHeaders: {'Idempotency-Key': idempotencyKey},
    );
  }

  Future<Map<String, dynamic>> verifyCreditPurchase({
    required String purchaseId,
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    return _request(
      'POST',
      '/api/credit-purchases/verify',
      body: {
        'purchase_id': purchaseId,
        'razorpay_order_id': orderId,
        'razorpay_payment_id': paymentId,
        'razorpay_signature': signature,
      },
    );
  }

  // Books (Catalog)
  Future<List<LibraryBook>> getBooks() async {
    final result = await _request('GET', '/api/books');
    final rawBooks = result['books'] as List? ?? [];
    return rawBooks
        .map((e) => LibraryBook.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList(growable: false);
  }

  Future<List<CatalogBook>> getFeaturedCatalogBooks() async {
    final result = await _request('GET', '/api/book-catalog');
    final raw = result['books'] as List? ?? [];
    return raw
        .map(
          (book) => CatalogBook.fromMap(Map<String, dynamic>.from(book as Map)),
        )
        .toList(growable: false);
  }

  Stream<List<LibraryBook>> watchBooks() async* {
    yield await getBooks();
  }

  // Exchange Listings (Peer-to-Peer)
  Future<List<MarketplaceListing>> getListings({
    String? category,
    String? query,
    String? ownerId,
    String? status,
  }) async {
    final queryParams = <String, String>{};
    if (category != null && category != 'All') {
      queryParams['category'] = category;
    }
    if (query != null && query.isNotEmpty) {
      queryParams['q'] = query;
    }
    if (ownerId != null) {
      queryParams['owner_id'] = ownerId;
    }
    if (status != null) {
      queryParams['status'] = status;
    }

    final result = await _request(
      'GET',
      '/api/listings',
      queryParams: queryParams.isNotEmpty ? queryParams : null,
    );
    final raw = result['listings'] as List? ?? [];
    return raw
        .map(
          (e) =>
              MarketplaceListing.fromMap(Map<String, dynamic>.from(e as Map)),
        )
        .toList(growable: false);
  }

  Future<MarketplaceListing> getListing(String id) async {
    final result = await _request('GET', '/api/listings/$id');
    return MarketplaceListing.fromMap(
      Map<String, dynamic>.from(result['listing'] as Map),
    );
  }

  Future<void> createListing({
    required String title,
    required String author,
    required String description,
    required String category,
    required String condition,
    required int creditValue,
    String? coverUrl,
  }) async {
    await _request(
      'POST',
      '/api/listings',
      body: {
        'title': title.trim(),
        'author': author.trim(),
        'description': description.trim(),
        'category': category,
        'condition': condition,
        'credit_value': creditValue,
        'cover_image_url': coverUrl,
      },
    );
  }

  Future<String> uploadBookCover({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    const allowedTypes = {'image/jpeg', 'image/png', 'image/webp'};
    if (bytes.isEmpty || bytes.length > 8 * 1024 * 1024) {
      throw Exception('Choose an image smaller than 8 MB.');
    }
    if (!allowedTypes.contains(mimeType.toLowerCase())) {
      throw Exception('Choose a JPEG, PNG, or WebP image.');
    }

    final signatureResponse = await _request('POST', '/api/uploads/signature');
    final cloudName = signatureResponse['cloud_name'] as String?;
    final fields = <String, String>{};
    for (final key in [
      'api_key',
      'folder',
      'public_id',
      'signature',
      'timestamp',
    ]) {
      final value = signatureResponse[key];
      if (value is! String || value.isEmpty) {
        throw Exception('Image upload configuration is incomplete.');
      }
      fields[key] = value;
    }
    if (cloudName == null ||
        !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(cloudName)) {
      throw Exception('Image upload configuration is invalid.');
    }

    final request =
        http.MultipartRequest(
            'POST',
            Uri.https('api.cloudinary.com', '/v1_1/$cloudName/image/upload'),
          )
          ..fields.addAll(fields)
          ..files.add(
            http.MultipartFile.fromBytes('file', bytes, filename: fileName),
          );
    final streamedResponse = await _client.send(request);
    final response = await http.Response.fromStream(streamedResponse);
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw Exception('Image service returned an invalid response.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map && decoded['error'] is Map
          ? (decoded['error'] as Map)['message']
          : null;
      throw Exception(
        message is String
            ? message
            : 'Image upload failed (${response.statusCode}).',
      );
    }
    if (decoded is! Map || decoded['secure_url'] is! String) {
      throw Exception('Image service did not return a secure image URL.');
    }
    final uploadedUri = Uri.tryParse(decoded['secure_url'] as String);
    if (uploadedUri == null ||
        uploadedUri.scheme != 'https' ||
        uploadedUri.host != 'res.cloudinary.com') {
      throw Exception('Image service returned an invalid image URL.');
    }
    return uploadedUri.toString();
  }

  Future<void> deleteListing(String listingId) async {
    await _request('DELETE', '/api/listings/$listingId');
  }

  // Wanted Books
  Future<List<WantedBook>> getWantedBooks() async {
    final result = await _request('GET', '/api/wanted-books');
    final raw = result['wanted_books'] as List? ?? [];
    return raw
        .map((e) => WantedBook.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList(growable: false);
  }

  Future<void> createWantedBook({
    required String title,
    required String author,
    String category = 'Fiction',
    int maxCredits = 10,
    String? notes,
  }) async {
    await _request(
      'POST',
      '/api/wanted-books',
      body: {
        'title': title.trim(),
        'author': author.trim(),
        'category': category,
        'max_credits': maxCredits,
        'notes': notes?.trim(),
      },
    );
  }

  Future<void> deleteWantedBook(String wantedId) async {
    await _request('DELETE', '/api/wanted-books/$wantedId');
  }

  Future<String> createMarketplaceOrder({
    required String listingId,
    required String idempotencyKey,
    required Map<String, String> shippingAddress,
  }) async {
    final result = await _request(
      'POST',
      '/api/marketplace/orders',
      body: {'listing_id': listingId, 'shipping_address': shippingAddress},
      extraHeaders: {'Idempotency-Key': idempotencyKey},
    );
    return result['id'] as String;
  }

  Future<List<MarketplaceOrder>> getMarketplaceOrders() async {
    final result = await _request('GET', '/api/marketplace/orders');
    final currentId = currentUser?.id ?? '';
    final raw = result['orders'] as List? ?? [];
    return raw
        .map(
          (order) => MarketplaceOrder.fromMap(
            Map<String, dynamic>.from(order as Map),
            currentId,
          ),
        )
        .toList(growable: false);
  }

  Future<void> updateMarketplaceShipping({
    required String orderId,
    required String carrier,
    required String trackingNumber,
  }) async {
    await _request(
      'POST',
      '/api/marketplace/orders/${Uri.encodeComponent(orderId)}/ship',
      body: {'shipping_carrier': carrier, 'tracking_number': trackingNumber},
    );
  }

  Future<void> confirmMarketplaceDelivery(String orderId) async {
    await _request(
      'POST',
      '/api/marketplace/orders/${Uri.encodeComponent(orderId)}/delivered',
    );
  }

  // Reviews
  Future<void> submitReview({
    required String exchangeId,
    required int rating,
    required String review,
  }) async {
    await _request(
      'POST',
      '/api/reviews',
      body: {
        'exchange_id': exchangeId,
        'rating': rating,
        'review': review.trim(),
      },
    );
  }

  // Community Activity
  Future<List<ActivityItem>> getActivity() async {
    final result = await _request('GET', '/api/activity');
    final raw = result['activities'] as List? ?? [];
    return raw
        .map((e) => ActivityItem.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList(growable: false);
  }

  // Notifications
  Future<List<LibraryNotification>> getNotifications() async {
    final result = await _request('GET', '/api/notifications');
    final raw = result['notifications'] as List? ?? [];
    return raw
        .map(
          (e) =>
              LibraryNotification.fromMap(Map<String, dynamic>.from(e as Map)),
        )
        .toList(growable: false);
  }

  Future<void> markNotificationRead(String notificationId) async {
    await _request(
      'POST',
      '/api/notifications/read',
      body: {'notification_id': notificationId},
    );
  }

  Future<void> markAllNotificationsRead() async {
    await _request('POST', '/api/notifications/read-all');
  }

  // Saved Books
  Future<List<Map<String, dynamic>>> getSavedBooks() async {
    final result = await _request('GET', '/api/saved-books');
    final raw = result['saved_books'] as List? ?? [];
    return raw
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  Future<void> saveBook({
    required String title,
    required String author,
    required String category,
    String? coverUrl,
  }) async {
    await _request(
      'POST',
      '/api/saved-books',
      body: {
        'title': title.trim(),
        'author': author.trim(),
        'category': category,
        'cover_url': coverUrl,
      },
    );
  }

  Future<void> removeSavedBook(String title) async {
    await _request('POST', '/api/saved-books/remove', body: {'title': title});
  }

  // Admin
  Future<Map<String, dynamic>> getAdminStats() async {
    final result = await _request('GET', '/api/admin/stats');
    return Map<String, dynamic>.from(result['stats'] as Map);
  }
}
