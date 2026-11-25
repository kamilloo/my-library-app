import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_library/services/open_library_service.dart';

void main() {
  const isbn = '080442957X';

  test('ISBN lookup distinguishes no match from an invalid response', () async {
    final empty = OpenLibraryService(
        client: MockClient((_) async => http.Response('{"docs":[]}', 200)));
    expect(await empty.lookupByIsbn(isbn), isNull);
    for (final body in [
      '{}',
      '{"docs":[1]}',
      '{"docs":[{}]}',
      'invalid JSON'
    ]) {
      final service = OpenLibraryService(
          client: MockClient((_) async => http.Response(body, 200)));
      await expectLater(
        service.lookupByIsbn(isbn),
        throwsA(predicate((Object error) =>
            openLibraryErrorMessage(error) ==
            'Nieprawidłowy format odpowiedzi Open Library.')),
      );
    }
  });

  test('ISBN lookup reports network failure and retries after recovery',
      () async {
    var connected = false;
    final service = OpenLibraryService(client: MockClient((_) async {
      if (!connected) throw http.ClientException('Network unavailable');
      return http.Response('{"docs":[{"title":"Title"}]}', 200);
    }));
    await expectLater(
      service.lookupByIsbn(isbn),
      throwsA(predicate((Object error) =>
          openLibraryErrorMessage(error) == openLibraryNetworkMessage)),
    );
    connected = true;
    expect((await service.lookupByIsbn(isbn))?.title, 'Title');
  });

  test('ISBN HTTP errors are distinct from connectivity failures', () async {
    final service = OpenLibraryService(
        client: MockClient((_) async => http.Response('', 503)));
    await expectLater(
      service.lookupByIsbn(isbn),
      throwsA(predicate((Object error) =>
          openLibraryErrorMessage(error) ==
          'Open Library zwróciło błąd HTTP 503.')),
    );
  });

  test('ISBN timeout bounds waiting for the response', () async {
    final pending = Completer<http.Response>();
    final service = OpenLibraryService(
      client: MockClient((_) => pending.future),
      searchTimeout: const Duration(milliseconds: 1),
    );
    await expectLater(
        service.lookupByIsbn(isbn), throwsA(isA<TimeoutException>()));
    pending.complete(http.Response('{"docs":[]}', 200));
  });

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
