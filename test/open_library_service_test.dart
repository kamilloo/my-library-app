import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_library/services/open_library_service.dart';

void main() {
  test('shared service reads metadata and optional work description', () async {
    final requests = <Uri>[];
    final service = OpenLibraryService(client: MockClient((request) async {
      requests.add(request.url);
      if (request.url.path == '/search.json') {
        return http.Response(jsonEncode({
          'docs': [
            {
              'title': 'Title',
              'author_name': ['Author'],
              'cover_i': 42,
              'key': '/works/OL1W',
            }
          ],
        }), 200);
      }
      return http.Response(
          jsonEncode({'description': {'value': 'Description'}}), 200);
    }));
    final book = await service.lookupByIsbn('080442957X');
    expect(book!.title, 'Title');
    expect(book.author, 'Author');
    expect(book.description, 'Description');
    expect(book.coverUrl, 'https://covers.openlibrary.org/b/id/42-M.jpg');
    expect(requests.first.queryParameters['q'], 'isbn:080442957X');
    expect(requests.last.path, '/works/OL1W.json');
  });

  test('optional description failure retains found metadata', () async {
    final service = OpenLibraryService(client: MockClient((request) async {
      if (request.url.path == '/search.json') {
        return http.Response(
            '{"docs":[{"title":"Title","key":"/works/OL1W"}]}', 200);
      }
      throw http.ClientException('offline');
    }));
    final book = await service.lookupByIsbn('080442957X');
    expect(book!.title, 'Title');
    expect(book.description, isNull);
  });
}
