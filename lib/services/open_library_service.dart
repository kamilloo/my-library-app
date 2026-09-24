import 'dart:convert';

import 'package:http/http.dart' as http;

class OpenLibraryBook {
  const OpenLibraryBook({required this.title, required this.author, this.coverUrl});
  final String title;
  final String author;
  final String? coverUrl;
}

class OpenLibraryService {
  OpenLibraryService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Future<OpenLibraryBook?> lookupByIsbn(String isbn) async {
    final uri = Uri.https('openlibrary.org', '/api/books', {
      'bibkeys': 'ISBN:$isbn',
      'format': 'json',
      'jscmd': 'data',
    });
    final response = await _client.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final book = data['ISBN:$isbn'] as Map<String, dynamic>?;
    if (book == null) return null;
    final authors = (book['authors'] as List<dynamic>?) ?? const [];
    final cover = book['cover'] as Map<String, dynamic>?;
    return OpenLibraryBook(
      title: (book['title'] as String?) ?? 'Unknown title',
      author: authors.isEmpty
          ? 'Unknown author'
          : authors.map((item) => (item as Map<String, dynamic>)['name']).join(', '),
      coverUrl: cover?['medium'] as String?,
    );
  }
}
