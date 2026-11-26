import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/open_library_search.dart';
import 'open_library_connectivity.dart'
    if (dart.library.js_interop) 'open_library_connectivity_web.dart';

const openLibraryNetworkMessage =
    'Nie udało się połączyć z Open Library. Sprawdź połączenie i spróbuj ponownie.';
const openLibraryOfflineMessage =
    'Przeglądarka jest w trybie offline. Połącz się z internetem lub wpisz dane ręcznie.';
const openLibraryBrowserMessage =
    'Nie udało się pobrać danych z Open Library w przeglądarce. Spróbuj ponownie lub wpisz dane ręcznie.';
const openLibraryTimeoutMessage =
    'Open Library nie odpowiedziało w wyznaczonym czasie. Spróbuj ponownie.';
const openLibraryNoMatchMessage =
    'Nie znaleziono książki. Możesz wpisać dane ręcznie.';

String openLibraryErrorMessage(Object error) => switch (error) {
      TimeoutException() => openLibraryTimeoutMessage,
      OpenLibrarySearchException(:final message) => message,
      _ => 'Nie udało się pobrać danych książki. Spróbuj ponownie.',
    };

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
    final data = await _request(uri);
    final docs = data['docs'] as List;
    final results = <OpenLibrarySearchResult>[];
    for (final doc in docs.take(searchPageSize)) {
      if (doc is! Map<String, dynamic>) throw _invalidResponse;
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
  }

  final http.Client _client;

  Future<OpenLibraryBook?> lookupByIsbn(String isbn) async {
    final uri = Uri.https('openlibrary.org', '/search.json', {
      'q': 'isbn:$isbn',
      'fields': 'title,author_name,cover_i',
      'limit': '1',
    });
    final documents = (await _request(uri))['docs'] as List;
    if (documents.isEmpty) return null;
    final book = documents.first;
    if (book is! Map<String, dynamic> ||
        book['title'] is! String ||
        (book['title'] as String).trim().isEmpty) {
      throw _invalidResponse;
    }
    final metadata = OpenLibrarySearchResult.fromJson(book);
    return OpenLibraryBook(
      title: metadata.title,
      author: metadata.author,
      coverUrl: metadata.coverUrl,
    );
  }

  static const _invalidResponse = OpenLibrarySearchException(
      'Nieprawidłowy format odpowiedzi Open Library.');

  Future<Map<String, dynamic>> _request(Uri uri) async {
    try {
      final response = await _client.get(uri, headers: const {
        if (!kIsWeb) 'User-Agent': 'MyLibraryApp/0.1',
        'Accept': 'application/json',
      }).timeout(searchTimeout);
      if (response.statusCode != 200) {
        throw OpenLibrarySearchException(
          switch (response.statusCode) {
            403 => 'Open Library odmówiło dostępu (HTTP 403).',
            429 =>
              'Open Library otrzymało zbyt wiele zapytań (HTTP 429). Spróbuj za chwilę.',
            >= 500 =>
              'Open Library jest chwilowo niedostępne (HTTP ${response.statusCode}). Spróbuj później.',
            _ => 'Open Library zwróciło błąd HTTP ${response.statusCode}.',
          },
        );
      }
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic> || data['docs'] is! List) {
        throw _invalidResponse;
      }
      return data;
    } on http.ClientException {
      throw OpenLibrarySearchException(
        !kIsWeb
            ? openLibraryNetworkMessage
            : browserReportsOffline
                ? openLibraryOfflineMessage
                : openLibraryBrowserMessage,
      );
    } on FormatException {
      throw _invalidResponse;
    }
  }
}
