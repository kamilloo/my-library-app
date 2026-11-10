import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/open_library_search.dart';

class OpenLibraryBook {
  const OpenLibraryBook(
      {required this.title, required this.author, this.coverUrl});
  final String title;
  final String author;
  final String? coverUrl;
}

class OpenLibraryService {
  OpenLibraryService(
      {http.Client? client, this.searchTimeout = const Duration(seconds: 10)})
      : _client = client ?? http.Client();
  final Duration searchTimeout;
  static const searchPageSize = 20;
  static const maxSearchPages = 5;

  Future<OpenLibrarySearchPage> searchBooks({
    String title = '',
    String author = '',
    int page = 1,
  }) async {
    title = title.trim();
    author = author.trim();
    if (title.isEmpty && author.isEmpty) {
      throw ArgumentError('Wpisz tytuł lub autora.');
    }
    if (page < 1 || page > maxSearchPages) {
      throw ArgumentError('Nieprawidłowa strona wyszukiwania.');
    }
    final uri = Uri.https('openlibrary.org', '/search.json', {
      if (title.isNotEmpty) 'title': title,
      if (author.isNotEmpty) 'author': author,
      'fields':
          'key,title,author_name,cover_i,first_publish_year,edition_key,isbn',
      'limit': '$searchPageSize',
      'page': '$page',
    });
    try {
      final response = await _client.get(uri, headers: const {
        'User-Agent': 'MyLibraryApp/0.1',
        'Accept': 'application/json',
      }).timeout(searchTimeout);
      if (response.statusCode != 200) {
        throw OpenLibrarySearchException(
            'Open Library zwróciło błąd HTTP ${response.statusCode}.');
      }
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic> || data['docs'] is! List) {
        throw const FormatException();
      }
      final docs = data['docs'] as List;
      final results = <OpenLibrarySearchResult>[];
      for (final doc in docs.take(searchPageSize)) {
        if (doc is! Map<String, dynamic>) throw const FormatException();
        results.add(OpenLibrarySearchResult.fromJson(doc));
      }
      final total = data['numFound'] ?? data['num_found'];
      return OpenLibrarySearchPage(
        results: results,
        hasMore: page < maxSearchPages &&
            (total is int
                ? page * searchPageSize < total
                : docs.length >= searchPageSize),
      );
    } on http.ClientException {
      throw const OpenLibrarySearchException(
          'Brak połączenia z internetem. Sprawdź połączenie.');
    } on FormatException {
      throw const OpenLibrarySearchException(
          'Nieprawidłowy format odpowiedzi Open Library.');
    }
  }

  final http.Client _client;

  Future<OpenLibraryBook?> lookupByIsbn(String isbn) async {
    final uri = Uri.https('openlibrary.org', '/search.json', {
      'q': 'isbn:$isbn',
      'fields': 'title,author_name,cover_i',
      'limit': '1',
    });
    final response = await _client.get(
      uri,
      headers: const {
        'User-Agent': 'MyLibraryApp/0.1',
        'Accept': 'application/json',
      },
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Open Library returned HTTP ${response.statusCode}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final documents = data['docs'] as List<dynamic>? ?? const [];
    if (documents.isEmpty) return null;
    final book = documents.first as Map<String, dynamic>;
    final authors = (book['author_name'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList();
    final coverId = book['cover_i'];
    return OpenLibraryBook(
      title: (book['title'] as String?) ?? 'Unknown title',
      author: authors.isEmpty ? 'Unknown author' : authors.join(', '),
      coverUrl: coverId == null
          ? null
          : 'https://covers.openlibrary.org/b/id/$coverId-M.jpg',
    );
  }
}
