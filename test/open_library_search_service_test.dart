import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_library/models/open_library_search.dart';
import 'package:my_library/services/open_library_service.dart';

void main() {
  for (final query in [
    {'title': '  Żółć & książka?  ', 'author': ''},
    {'title': '', 'author': '  Łukasz Ćma  '},
    {'title': '  Pan Tadeusz ', 'author': ' Adam Mickiewicz  '},
  ]) {
    test('title/author query trims and safely encodes $query', () async {
      final requests = <Uri>[];
      final service = OpenLibraryService(client: MockClient((request) async {
        requests.add(request.url);
        return http.Response('{"docs":[]}', 200);
      }));
      await service.searchBooks(
          title: query['title']!, author: query['author']!);
      final url = requests.single;
      expect(url.scheme, 'https');
      expect(url.host, 'openlibrary.org');
      expect(url.path, '/search.json');
      for (final key in ['title', 'author']) {
        expect(url.queryParameters[key],
            query[key]!.trim().isEmpty ? isNull : query[key]!.trim());
      }
      expect(url.queryParameters['fields'],
          'key,title,author_name,cover_i,first_publish_year,edition_key,isbn');
      expect(url.queryParameters['limit'], '20');
      expect(url.queryParameters['page'], '1');
    });
  }

  test('empty queries and out-of-range pages never request HTTP', () async {
    var calls = 0;
    final service = OpenLibraryService(client: MockClient((_) async {
      calls++;
      return http.Response('{}', 200);
    }));
    await expectLater(
        service.searchBooks(title: ' ', author: '\t'), throwsArgumentError);
    for (final page in [0, 6]) {
      await expectLater(
          service.searchBooks(title: 'T', page: page), throwsArgumentError);
    }
    expect(calls, 0);
  });

  test(
      'multiple results parse optional fields defensively and never guess work ISBN',
      () async {
    final service = OpenLibraryService(
        client: MockClient((_) async => http.Response(
            jsonEncode({
              'docs': [
                {
                  'key': '/works/OL1W',
                  'title': 'Title',
                  'author_name': ['A', 'B'],
                  'cover_i': 42,
                  'first_publish_year': 1990,
                  'edition_key': ['OL1M', 'OL2M'],
                  'isbn': ['080442957X', '9780525559474']
                },
                {'title': 'Minimal'},
                {
                  'title': null,
                  'author_name': 'bad',
                  'cover_i': {},
                  'first_publish_year': 'bad',
                  'isbn': 42
                },
              ],
            }),
            200)));
    final response = await service.searchBooks(title: 'T');
    expect(response.results, hasLength(3));
    expect(response.results.first.author, 'A, B');
    expect(response.results.first.coverUrl,
        'https://covers.openlibrary.org/b/id/42-M.jpg');
    expect(response.results.first.year, 1990);
    expect(response.results.first.isbn, isNull);
    expect(response.results[1].author, isEmpty);
    expect(response.results[1].coverUrl, isNull);
    expect(response.results[2].title, 'Bez tytułu');
    expect(response.results[2].year, isNull);
  });

  test(
      'ISBN requires explicit matching edition and exactly one valid normalized value',
      () {
    final json = {
      'title': 'T',
      'key': '/books/OL1M',
      'edition_key': ['OL1M'],
      'isbn': ['0-8044-2957-x'],
    };
    expect(OpenLibrarySearchResult.fromJson(json).isbn, '080442957X');
    for (final change in [
      {'key': '/works/OL1W'},
      {
        'edition_key': ['OL2M']
      },
      {
        'edition_key': ['OL1M', 'OL2M']
      },
      {
        'isbn': ['080442957X', '9780525559474']
      },
      {
        'isbn': ['9780525559475']
      },
    ]) {
      expect(
          OpenLibrarySearchResult.fromJson({...json, ...change}).isbn, isNull);
    }
  });

  for (final body in ['not json', '[]', '{}', '{"docs":{}}', '{"docs":[1]}']) {
    test('invalid response $body produces Polish format error', () async {
      final service = OpenLibraryService(
          client: MockClient((_) async => http.Response(body, 200)));
      await expectLater(
          service.searchBooks(author: 'A'),
          throwsA(isA<OpenLibrarySearchException>()
              .having((e) => e.message, 'message', contains('format'))));
    });
  }

  test('HTTP and offline errors use Polish messages', () async {
    final httpService = OpenLibraryService(
        client: MockClient((_) async => http.Response('', 503)));
    await expectLater(
        httpService.searchBooks(title: 'T'),
        throwsA(isA<OpenLibrarySearchException>()
            .having((e) => e.message, 'message', contains('HTTP 503'))));
    final offline = OpenLibraryService(
        client: MockClient((_) async => throw http.ClientException('offline')));
    await expectLater(
        offline.searchBooks(author: 'A'),
        throwsA(isA<OpenLibrarySearchException>()
            .having((e) => e.message, 'message', contains('Brak połączenia'))));
  });

  test('timeout terminates waiting for the search response', () async {
    final pending = Completer<http.Response>();
    final service = OpenLibraryService(
        client: MockClient((_) => pending.future),
        searchTimeout: const Duration(milliseconds: 1));
    await expectLater(
        service.searchBooks(title: 'T'), throwsA(isA<TimeoutException>()));
    pending.complete(http.Response('{"docs":[]}', 200));
  });

  test('pagination is capped at 20 results and five pages', () async {
    final pages = <String?>[];
    final service = OpenLibraryService(client: MockClient((request) async {
      pages.add(request.url.queryParameters['page']);
      return http.Response(
          jsonEncode({
            'numFound': 999,
            'docs': List.generate(30, (i) => {'title': 'Book $i'}),
          }),
          200);
    }));
    for (var page = 1; page <= 5; page++) {
      final result = await service.searchBooks(title: 'T', page: page);
      expect(result.results, hasLength(20));
      expect(result.hasMore, page < 5);
    }
    expect(pages, ['1', '2', '3', '4', '5']);
  });
}
