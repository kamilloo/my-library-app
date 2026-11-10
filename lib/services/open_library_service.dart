import 'dart:convert';

import 'package:http/http.dart' as http;

class OpenLibraryBook {
  const OpenLibraryBook(
      {required this.title, required this.author, this.coverUrl, this.description});
  final String title;
  final String author;
  final String? coverUrl;
  final String? description;
}

class OpenLibraryService {
  OpenLibraryService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Future<OpenLibraryBook?> lookupByIsbn(String isbn) async {
    final uri = Uri.https('openlibrary.org', '/search.json', {
      'q': 'isbn:$isbn',
      'fields': 'title,author_name,cover_i,key',
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
    String? description;
    final key = book['key'];
    if (key is String && key.startsWith('/works/')) {
      try {
        final details = await _client.get(
          Uri.https('openlibrary.org', '$key.json'),
        ).timeout(const Duration(seconds: 10));
        if (details.statusCode == 200) {
          final work = jsonDecode(details.body) as Map<String, dynamic>;
          final value = work['description'];
          description = value is String
              ? value
              : value is Map ? value['value'] as String? : null;
        }
      } catch (_) {
        // Description is optional; keep the metadata already found.
      }
    }
    return OpenLibraryBook(
      description: description,
      title: (book['title'] as String?) ?? 'Unknown title',
      author: authors.isEmpty ? 'Unknown author' : authors.join(', '),
      coverUrl: coverId == null
          ? null
          : 'https://covers.openlibrary.org/b/id/$coverId-M.jpg',
    );
  }
}
