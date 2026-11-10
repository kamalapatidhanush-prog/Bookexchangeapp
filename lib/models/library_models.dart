num? _numberValue(Object? value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value);
  return null;
}

class LibraryBook {
  const LibraryBook({
    required this.id,
    required this.title,
    required this.author,
    required this.category,
    required this.description,
    required this.isbn,
    required this.totalCopies,
    required this.availableCopies,
    required this.createdAt,
    this.coverImageUrl,
    this.publisher,
    this.publicationYear,
  });

  factory LibraryBook.fromMap(Map<String, dynamic> map) {
    return LibraryBook(
      id: map['id'] as String,
      title: map['title'] as String? ?? '',
      author: map['author'] as String? ?? '',
      category: map['category'] as String? ?? 'General',
      description: map['description'] as String? ?? '',
      isbn: map['isbn'] as String? ?? '',
      totalCopies: (map['total_copies'] as num?)?.toInt() ?? 1,
      availableCopies: (map['available_copies'] as num?)?.toInt() ?? 1,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      coverImageUrl: map['cover_image_url'] as String?,
      publisher: map['publisher'] as String?,
      publicationYear: (map['publication_year'] as num?)?.toInt(),
    );
  }

  final String id;
  final String title;
  final String author;
  final String category;
  final String description;
  final String isbn;
  final int totalCopies;
  final int availableCopies;
  final DateTime createdAt;
  final String? coverImageUrl;
  final String? publisher;
  final int? publicationYear;

  bool get isAvailable => availableCopies > 0;
}

class MarketplaceListing {
  const MarketplaceListing({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.author,
    required this.category,
    required this.bookCondition,
    required this.description,
    required this.creditValue,
    required this.status,
    required this.createdAt,
    this.ownerName,
    this.ownerLocation,
    this.ownerRating,
    this.coverImageUrl,
  });

  factory MarketplaceListing.fromMap(Map<String, dynamic> map) {
    return MarketplaceListing(
      id: map['id'] as String,
      ownerId: map['owner_id'] as String? ?? '',
      title: map['title'] as String? ?? 'Untitled Book',
      author: map['author'] as String? ?? 'Unknown Author',
      category: map['category'] as String? ?? 'Fiction',
      bookCondition: map['book_condition'] as String? ?? 'Very Good',
      description: map['description'] as String? ?? '',
      creditValue: (map['credit_value'] as num?)?.toInt() ?? 10,
      status: map['status'] as String? ?? 'available',
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      ownerName: map['owner_name'] as String? ?? 'Community Reader',
      ownerLocation: map['owner_location'] as String? ?? 'Local Area',
      ownerRating: (map['owner_rating'] as num?)?.toDouble(),
      coverImageUrl: map['cover_image_url'] as String?,
    );
  }

  final String id;
  final String ownerId;
  final String title;
  final String author;
  final String category;
  final String bookCondition;
  final String description;
  final int creditValue;
  final String status;
  final DateTime createdAt;
  final String? ownerName;
  final String? ownerLocation;
  final double? ownerRating;
  final String? coverImageUrl;

  bool get isAvailable => status == 'available';
}

class MarketplaceOrder {
  const MarketplaceOrder({
    required this.id,
    required this.listingId,
    required this.buyerId,
    required this.sellerId,
    required this.credits,
    required this.status,
    required this.createdAt,
    required this.isSeller,
    required this.isBuyer,
    required this.title,
    required this.author,
    required this.buyerName,
    required this.sellerName,
    required this.recipientName,
    required this.recipientPhone,
    required this.addressLine1,
    required this.city,
    required this.region,
    required this.postalCode,
    required this.country,
    this.coverImageUrl,
    this.addressLine2,
    this.shippingCarrier,
    this.trackingNumber,
    this.shippedAt,
    this.deliveredAt,
    this.userReviewId,
  });

  factory MarketplaceOrder.fromMap(
    Map<String, dynamic> map,
    String currentUserId,
  ) {
    DateTime? date(String key) {
      final value = map[key];
      return value == null ? null : DateTime.tryParse(value.toString());
    }

    final buyerId = map['buyer_id'] as String? ?? '';
    final sellerId = map['seller_id'] as String? ?? '';
    return MarketplaceOrder(
      id: map['id'] as String,
      listingId: map['listing_id'] as String? ?? '',
      buyerId: buyerId,
      sellerId: sellerId,
      credits: (map['credits'] as num?)?.toInt() ?? 0,
      status: map['status'] as String? ?? 'paid',
      createdAt: date('created_at') ?? DateTime.now(),
      isSeller: sellerId == currentUserId,
      isBuyer: buyerId == currentUserId,
      title: map['title'] as String? ?? 'Book',
      author: map['author'] as String? ?? '',
      buyerName: map['buyer_name'] as String? ?? 'Reader',
      sellerName: map['seller_name'] as String? ?? 'Seller',
      coverImageUrl: map['cover_image_url'] as String?,
      recipientName: map['recipient_name'] as String? ?? '',
      recipientPhone: map['recipient_phone'] as String? ?? '',
      addressLine1: map['address_line1'] as String? ?? '',
      addressLine2: map['address_line2'] as String?,
      city: map['city'] as String? ?? '',
      region: map['region'] as String? ?? '',
      postalCode: map['postal_code'] as String? ?? '',
      country: map['country'] as String? ?? '',
      shippingCarrier: map['shipping_carrier'] as String?,
      trackingNumber: map['tracking_number'] as String?,
      shippedAt: date('shipped_at'),
      deliveredAt: date('delivered_at'),
      userReviewId: map['user_review_id'] as String?,
    );
  }

  final String id;
  final String listingId;
  final String buyerId;
  final String sellerId;
  final int credits;
  final String status;
  final DateTime createdAt;
  final bool isSeller;
  final bool isBuyer;
  final String title;
  final String author;
  final String buyerName;
  final String sellerName;
  final String? coverImageUrl;
  final String recipientName;
  final String recipientPhone;
  final String addressLine1;
  final String? addressLine2;
  final String city;
  final String region;
  final String postalCode;
  final String country;
  final String? shippingCarrier;
  final String? trackingNumber;
  final DateTime? shippedAt;
  final DateTime? deliveredAt;
  final String? userReviewId;

  bool get isPaid => status == 'paid';
  bool get isShipped => status == 'shipped';
  bool get isDelivered => status == 'delivered';
  bool get canReview => isDelivered && userReviewId == null;
  String get otherPartyName => isSeller ? buyerName : sellerName;
}

class WantedBook {
  const WantedBook({
    required this.id,
    required this.userId,
    required this.title,
    required this.author,
    required this.category,
    required this.maxCredits,
    required this.status,
    required this.createdAt,
    this.userName = 'Reader',
    this.userLocation = 'Local Area',
    this.notes,
  });

  factory WantedBook.fromMap(Map<String, dynamic> map) {
    return WantedBook(
      id: map['id'] as String,
      userId: map['user_id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      author: map['author'] as String? ?? '',
      category: map['category'] as String? ?? 'Fiction',
      maxCredits: (map['max_credits'] as num?)?.toInt() ?? 10,
      status: map['status'] as String? ?? 'open',
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      userName: map['user_name'] as String? ?? 'Reader',
      userLocation: map['user_location'] as String? ?? 'Local Area',
      notes: map['notes'] as String?,
    );
  }

  final String id;
  final String userId;
  final String title;
  final String author;
  final String category;
  final int maxCredits;
  final String status;
  final DateTime createdAt;
  final String userName;
  final String userLocation;
  final String? notes;
}

class CreditLedgerEntry {
  const CreditLedgerEntry({
    required this.id,
    required this.amount,
    required this.type,
    required this.createdAt,
    this.referenceId,
    this.description,
  });

  factory CreditLedgerEntry.fromMap(Map<String, dynamic> map) {
    return CreditLedgerEntry(
      id: map['id'] as String,
      amount: (map['amount'] as num?)?.toInt() ?? 0,
      type: map['type'] as String? ?? 'transaction',
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      referenceId: map['reference_id'] as String?,
      description: map['description'] as String?,
    );
  }

  final String id;
  final int amount;
  final String type;
  final DateTime createdAt;
  final String? referenceId;
  final String? description;

  bool get isPositive => amount > 0;
}

class CreditAccount {
  const CreditAccount({
    required this.balance,
    required this.ledger,
    this.summary = const CreditSummary(),
    this.hasMore = false,
    this.nextCursor,
  });

  final int balance;
  final List<CreditLedgerEntry> ledger;
  final CreditSummary summary;
  final bool hasMore;
  final String? nextCursor;
}

class CreditSummary {
  const CreditSummary({
    this.earned = 0,
    this.purchased = 0,
    this.spent = 0,
    this.held = 0,
    this.refunded = 0,
  });

  factory CreditSummary.fromMap(Map<String, dynamic>? map) {
    return CreditSummary(
      earned: _numberValue(map?['earned'])?.toInt() ?? 0,
      purchased: _numberValue(map?['purchased'])?.toInt() ?? 0,
      spent: _numberValue(map?['spent'])?.toInt() ?? 0,
      held: _numberValue(map?['held'])?.toInt() ?? 0,
      refunded: _numberValue(map?['refunded'])?.toInt() ?? 0,
    );
  }

  final int earned;
  final int purchased;
  final int spent;
  final int held;
  final int refunded;
}

class CreditPackage {
  const CreditPackage({
    required this.id,
    required this.name,
    required this.credits,
    required this.amountMinor,
    required this.currency,
    required this.popular,
  });

  factory CreditPackage.fromMap(Map<String, dynamic> map) {
    return CreditPackage(
      id: map['id'] as String,
      name: map['name'] as String,
      credits: (map['credits'] as num).toInt(),
      amountMinor: (map['amount_minor'] as num).toInt(),
      currency: map['currency'] as String? ?? 'INR',
      popular: map['popular'] == true,
    );
  }

  final String id;
  final String name;
  final int credits;
  final int amountMinor;
  final String currency;
  final bool popular;
}

class CreditStoreCatalog {
  const CreditStoreCatalog({
    required this.packages,
    required this.paymentsEnabled,
  });

  final List<CreditPackage> packages;
  final bool paymentsEnabled;
}

class CreditPurchase {
  const CreditPurchase({
    required this.id,
    required this.packageId,
    required this.packageName,
    required this.credits,
    required this.amountMinor,
    required this.currency,
    required this.paymentProvider,
    required this.status,
    required this.createdAt,
    this.paymentReference,
    this.checkoutKeyId,
    this.completedAt,
  });

  factory CreditPurchase.fromMap(Map<String, dynamic> map) {
    return CreditPurchase(
      id: map['id'] as String,
      packageId: map['package_id'] as String,
      packageName: map['package_name'] as String? ?? 'Credit package',
      credits: (map['credits'] as num).toInt(),
      amountMinor: (map['amount_minor'] as num).toInt(),
      currency: map['currency'] as String? ?? 'INR',
      paymentProvider: map['payment_provider'] as String? ?? '',
      paymentReference: map['payment_reference'] as String?,
      checkoutKeyId: map['checkout_key_id'] as String?,
      status: map['status'] as String? ?? 'pending',
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      completedAt: map['completed_at'] != null
          ? DateTime.tryParse(map['completed_at'] as String)
          : null,
    );
  }

  final String id;
  final String packageId;
  final String packageName;
  final int credits;
  final int amountMinor;
  final String currency;
  final String paymentProvider;
  final String? paymentReference;
  final String? checkoutKeyId;
  final String status;
  final DateTime createdAt;
  final DateTime? completedAt;
}

class LibraryNotification {
  const LibraryNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.isRead,
    required this.createdAt,
    this.referenceId,
  });

  factory LibraryNotification.fromMap(Map<String, dynamic> map) {
    return LibraryNotification(
      id: map['id'] as String,
      title: map['title'] as String? ?? 'Notification',
      body: map['body'] as String? ?? '',
      type: map['type'] as String? ?? 'system',
      isRead: map['is_read'] == true || map['is_read'] == 1,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      referenceId: map['reference_id'] as String?,
    );
  }

  final String id;
  final String title;
  final String body;
  final String type;
  final bool isRead;
  final DateTime createdAt;
  final String? referenceId;
}

class ActivityItem {
  const ActivityItem({
    required this.id,
    required this.userId,
    required this.actionType,
    required this.title,
    required this.description,
    required this.createdAt,
    this.userName = 'Community Member',
    this.referenceId,
  });

  factory ActivityItem.fromMap(Map<String, dynamic> map) {
    return ActivityItem(
      id: map['id'] as String,
      userId: map['user_id'] as String? ?? '',
      actionType: map['action_type'] as String? ?? 'update',
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      userName: map['user_name'] as String? ?? 'Community Member',
      referenceId: map['reference_id'] as String?,
    );
  }

  final String id;
  final String userId;
  final String actionType;
  final String title;
  final String description;
  final DateTime createdAt;
  final String userName;
  final String? referenceId;
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.name,
    required this.email,
    required this.location,
    required this.bio,
    required this.role,
    required this.credits,
    required this.soldCount,
    required this.purchasedCount,
    required this.listedCount,
    required this.rating,
    required this.reviewCount,
    required this.createdAt,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'] as String? ?? '',
      name: map['display_name'] as String? ?? 'Reader',
      email: map['email'] as String? ?? '',
      location: map['location'] as String? ?? 'Local Area',
      bio: map['bio'] as String? ?? '',
      role: map['role'] as String? ?? 'member',
      credits: (map['credits'] as num?)?.toInt() ?? 0,
      soldCount: (map['sold_count'] as num?)?.toInt() ?? 0,
      purchasedCount: (map['purchased_count'] as num?)?.toInt() ?? 0,
      listedCount: (map['listed_count'] as num?)?.toInt() ?? 0,
      rating: (map['rating'] as num?)?.toDouble(),
      reviewCount: (map['review_count'] as num?)?.toInt() ?? 0,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  final String id;
  final String name;
  final String email;
  final String location;
  final String bio;
  final String role;
  final int credits;
  final int soldCount;
  final int purchasedCount;
  final int listedCount;
  final double? rating;
  final int reviewCount;
  final DateTime createdAt;
}

class BookReview {
  const BookReview({
    required this.id,
    required this.reviewerName,
    required this.rating,
    required this.review,
    required this.createdAt,
  });

  factory BookReview.fromMap(Map<String, dynamic> map) {
    return BookReview(
      id: map['id'] as String,
      reviewerName: map['reviewer_name'] as String? ?? 'Fellow Reader',
      rating: (map['rating'] as num?)?.toInt() ?? 5,
      review: map['review'] as String? ?? '',
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  final String id;
  final String reviewerName;
  final int rating;
  final String review;
  final DateTime createdAt;
}

class Reservation {
  const Reservation({
    required this.id,
    required this.bookId,
    required this.title,
    required this.author,
    required this.status,
  });

  factory Reservation.fromMap(Map<String, dynamic> map) => Reservation(
    id: map['id'] as String,
    bookId: map['book_id'] as String? ?? '',
    title: map['title'] as String? ?? 'Book',
    author: map['author'] as String? ?? '',
    status: map['status'] as String? ?? 'waiting',
  );

  final String id;
  final String bookId;
  final String title;
  final String author;
  final String status;
}
