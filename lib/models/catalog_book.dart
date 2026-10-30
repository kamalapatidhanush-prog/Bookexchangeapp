class CatalogBook {
  const CatalogBook({
    required this.key,
    required this.title,
    required this.author,
    required this.coverUrl,
    this.firstPublishYear,
  });

  factory CatalogBook.fromMap(Map<String, dynamic> map) {
    return CatalogBook(
      key: map['key'] as String,
      title: map['title'] as String,
      author: map['author'] as String? ?? 'Unknown author',
      coverUrl: map['cover_url'] as String,
      firstPublishYear: (map['first_publish_year'] as num?)?.toInt(),
    );
  }

  final String key;
  final String title;
  final String author;
  final String coverUrl;
  final int? firstPublishYear;
}
