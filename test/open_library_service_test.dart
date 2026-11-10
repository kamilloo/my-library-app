import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_library/services/open_library_service.dart';

void main() {
  test('shared scanner service fetches title author and cover in one request',
      () async {
    final requests = <Uri>[];
    final service = OpenLibraryService(client: MockClient((request) async {
      requests.add(request.url);
      return http.Response(
          jsonEncode({
            'docs': [
              {
                'title': 'Title',
                'author_name': ['Author'],
                'cover_i': 42,
                'key': '/works/OL1W',
              }
            ],
          }),
          200);
    }));
    final book = await service.lookupByIsbn('080442957X');
    expect(book!.title, 'Title');
    expect(book.author, 'Author');
    expect(book.coverUrl, 'https://covers.openlibrary.org/b/id/42-M.jpg');
    expect(requests, hasLength(1));
    expect(requests.single.path, '/search.json');
    expect(requests.single.queryParameters['q'], 'isbn:080442957X');
    expect(
        requests.single.queryParameters['fields'], 'title,author_name,cover_i');
  });
}
