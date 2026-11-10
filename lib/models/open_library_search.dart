import 'isbn.dart';

class OpenLibrarySearchResult {
  const OpenLibrarySearchResult({
    required this.title,
    required this.author,
    this.key,
    this.coverUrl,
    this.year,
    this.isbn,
  });
  final String title;
  final String author;
  final String? key;
  final String? coverUrl;
  final int? year;
  final String? isbn;

  factory OpenLibrarySearchResult.fromJson(Map<String, dynamic> json) {
    List<String> strings(Object? value) => value is List
        ? value
            .whereType<String>()
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
        : const [];
    final key = json['key'] is String ? json['key'] as String : null;
    final editions = strings(json['edition_key']);
    final isbns =
        strings(json['isbn']).map(normalizeIsbn).whereType<String>().toSet();
    // Work search does not identify the user's physical edition. Only accept
    // an explicit edition record with one matching edition and one valid ISBN.
    final edition = key != null && RegExp(r'^/books/OL[0-9]+M$').hasMatch(key)
        ? key.substring(7)
        : null;
    final confident = edition != null &&
        editions.length == 1 &&
        editions.single == edition &&
        isbns.length == 1;
    final cover = json['cover_i'];
    final year = json['first_publish_year'];
    final title = json['title'];
    return OpenLibrarySearchResult(
      key: key,
      title: title is String && title.trim().isNotEmpty
          ? title.trim()
          : 'Bez tytułu',
      author: strings(json['author_name']).join(', '),
      coverUrl: cover is int && cover > 0
          ? 'https://covers.openlibrary.org/b/id/$cover-M.jpg'
          : null,
      year: year is int && year > 0 ? year : null,
      isbn: confident ? isbns.single : null,
    );
  }
}

class OpenLibrarySearchPage {
  const OpenLibrarySearchPage({required this.results, required this.hasMore});
  final List<OpenLibrarySearchResult> results;
  final bool hasMore;
}

class OpenLibrarySearchException implements Exception {
  const OpenLibrarySearchException(this.message);
  final String message;
  @override
  String toString() => message;
}
