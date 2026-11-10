import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/main.dart';
import 'package:my_library/models/open_library_search.dart';
import 'package:my_library/screens/book_cover.dart';
import 'package:my_library/screens/search_books_screen.dart';
import 'package:my_library/services/open_library_service.dart';

import 'cover_form_test.dart' show Picker, Repository;

class SearchService extends OpenLibraryService {
  final calls = <({String title, String author, int page})>[];
  Future<OpenLibrarySearchPage> Function(int page) response =
      (_) async => const OpenLibrarySearchPage(results: [], hasMore: false);
  @override
  Future<OpenLibrarySearchPage> searchBooks(
      {String title = '', String author = '', int page = 1}) {
    calls.add((title: title, author: author, page: page));
    return response(page);
  }
}

const remoteResult = OpenLibrarySearchResult(
  title: 'Remote title',
  author: 'Remote author',
  year: 1999,
  coverUrl: 'https://example.com/cover.jpg',
);
const resultPage =
    OpenLibrarySearchPage(results: [remoteResult], hasMore: false);

void main() {
  Future<void> size(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  Future<void> search(WidgetTester tester) async {
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Szukaj'));
    await tester.pump();
  }

  Future<void> startFromForm(WidgetTester tester) async {
    final entry = find.text('Szukaj książki po tytule lub autorze');
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    await search(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wybierz książkę'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'empty search makes no request; loading prevents duplicates and displays results',
      (tester) async {
    await size(tester);
    final service = SearchService();
    final pending = Completer<OpenLibrarySearchPage>();
    service.response = (_) => pending.future;
    await tester
        .pumpWidget(MaterialApp(home: SearchBooksScreen(service: service)));
    expect(service.calls, isEmpty);
    await search(tester);
    expect(find.text('Wpisz tytuł lub autora.'), findsOneWidget);
    expect(service.calls, isEmpty);
    await tester.enterText(find.byType(TextField).first, '  Tytuł  ');
    await search(tester);
    await search(tester);
    expect(find.text('Wyszukiwanie…'), findsOneWidget);
    expect(service.calls, hasLength(1));
    expect(service.calls.single.title, 'Tytuł');
    pending.complete(resultPage);
    await tester.pumpAndSettle();
    expect(find.text('Remote title'), findsOneWidget);
    expect(find.text('Remote author'), findsOneWidget);
    expect(find.text('Rok wydania: 1999'), findsOneWidget);
  });

  testWidgets('new searches ignore older out-of-order responses',
      (tester) async {
    await size(tester);
    final service = SearchService();
    final first = Completer<OpenLibrarySearchPage>();
    final second = Completer<OpenLibrarySearchPage>();
    service.response =
        (_) => service.calls.length == 1 ? first.future : second.future;
    await tester
        .pumpWidget(MaterialApp(home: SearchBooksScreen(service: service)));
    await tester.enterText(find.byType(TextField).first, 'Old query');
    await search(tester);
    await tester.enterText(find.byType(TextField).first, 'New query');
    await search(tester);
    second.complete(resultPage);
    await tester.pumpAndSettle();
    first.complete(const OpenLibrarySearchPage(results: [
      OpenLibrarySearchResult(title: 'Stale result', author: 'Stale'),
    ], hasMore: false));
    await tester.pumpAndSettle();
    expect(find.text('Stale result'), findsNothing);
    expect(find.text('Remote title'), findsOneWidget);
  });

  for (final error in [
    TimeoutException('timeout'),
    const OpenLibrarySearchException('Brak połączenia z internetem.'),
    const OpenLibrarySearchException('Open Library zwróciło błąd HTTP 503.'),
    const OpenLibrarySearchException(
        'Nieprawidłowy format odpowiedzi Open Library.'),
  ]) {
    testWidgets('search error supports retry: $error', (tester) async {
      await size(tester);
      final service = SearchService()..response = (_) async => throw error;
      await tester
          .pumpWidget(MaterialApp(home: SearchBooksScreen(service: service)));
      await tester.enterText(find.byType(TextField).last, 'Author');
      await search(tester);
      await tester.pumpAndSettle();
      expect(find.text('Spróbuj ponownie'), findsOneWidget);
      expect(find.text('Author'), findsOneWidget);
      service.response =
          (_) async => const OpenLibrarySearchPage(results: [], hasMore: false);
      await tester.tap(find.text('Spróbuj ponownie'));
      await tester.pumpAndSettle();
      expect(
          find.text(
              'Nie znaleziono książek. Spróbuj zmienić tytuł lub autora.'),
          findsOneWidget);
    });
  }

  testWidgets('revisiting an identical pending query reuses its HTTP future',
      (tester) async {
    await size(tester);
    final service = SearchService();
    final pending = Completer<OpenLibrarySearchPage>();
    service.response = (_) => pending.future;
    await tester
        .pumpWidget(MaterialApp(home: SearchBooksScreen(service: service)));
    await tester.enterText(find.byType(TextField).first, 'Query');
    await search(tester);
    await tester.enterText(find.byType(TextField).first, '  Query  ');
    await search(tester);
    expect(service.calls, hasLength(1));
    pending.complete(resultPage);
    await tester.pumpAndSettle();
    expect(find.text('Remote title'), findsOneWidget);
  });

  testWidgets('failed search can be canceled and a manual book saved',
      (tester) async {
    await size(tester);
    final service = SearchService()
      ..response = (_) async => throw const OpenLibrarySearchException(
          'Brak połączenia z internetem.');
    final repository = Repository();
    await tester.pumpWidget(MaterialApp(
        home: AddBookScreen(repository: repository, isbnService: service)));
    await tester.enterText(find.byType(TextFormField).at(0), 'Offline title');
    await tester.enterText(find.byType(TextFormField).at(1), 'Offline author');
    await tester.tap(find.text('Szukaj książki po tytule lub autorze'));
    await tester.pumpAndSettle();
    await search(tester);
    await tester.pumpAndSettle();
    expect(find.text('Spróbuj ponownie'), findsOneWidget);
    Navigator.of(tester.element(find.byType(SearchBooksScreen))).pop();
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, 'Zapisz książkę');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(repository.savedTitle, 'Offline title');
    expect(repository.savedAuthor, 'Offline author');
  });

  testWidgets('pagination requires taps and stops after five pages',
      (tester) async {
    await size(tester);
    final service = SearchService()
      ..response = (page) async => OpenLibrarySearchPage(results: [
            OpenLibrarySearchResult(title: 'Page $page', author: ''),
          ], hasMore: true);
    await tester
        .pumpWidget(MaterialApp(home: SearchBooksScreen(service: service)));
    await tester.enterText(find.byType(TextField).first, 'Title');
    await search(tester);
    await tester.pumpAndSettle();
    expect(service.calls, hasLength(1));
    for (var page = 2; page <= 5; page++) {
      await tester.tap(find.text('Pokaż więcej'));
      await tester.pumpAndSettle();
      expect(service.calls.last.page, page);
    }
    expect(find.text('Pokaż więcej'), findsNothing);
    expect(service.calls, hasLength(5));
  });

  testWidgets('cancel search preserves entered form data', (tester) async {
    await size(tester);
    final service = SearchService();
    await tester.pumpWidget(MaterialApp(
        home: AddBookScreen(repository: Repository(), isbnService: service)));
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'My title');
    await tester.enterText(fields.at(1), 'My author');
    await tester.enterText(fields.at(2), '080442957X');
    await tester.tap(find.text('Szukaj książki po tytule lub autorze'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(SearchBooksScreen))).pop();
    await tester.pumpAndSettle();
    expect(find.text('My title'), findsOneWidget);
    expect(find.text('My author'), findsOneWidget);
    expect(find.text('080442957X'), findsOneWidget);
    expect(service.calls, isEmpty);
  });

  for (final replace in [false, true]) {
    testWidgets(
        'confirmation preserves or explicitly replaces title author and local cover: $replace',
        (tester) async {
      await size(tester);
      final service = SearchService()..response = (_) async => resultPage;
      final picker = Picker()..result = '/temporary/local.jpg';
      final repository = Repository();
      await tester.pumpWidget(MaterialApp(
          home: AddBookScreen(
              repository: repository,
              isbnService: service,
              coverPicker: picker)));
      await tester.tap(find.text('Wybierz zdjęcie z urządzenia'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'My title');
      await tester.enterText(find.byType(TextFormField).at(1), 'My author');
      await tester.enterText(find.byType(TextFormField).at(2), '080442957X');
      await startFromForm(tester);
      expect(find.text('Zastąpić wpisane dane?'), findsOneWidget);
      await tester.tap(find.text(
          replace ? 'Zastąp wpisane dane' : 'Uzupełnij tylko puste pola'));
      await tester.pumpAndSettle();
      expect(find.text(replace ? 'Remote title' : 'My title'), findsOneWidget);
      expect(
          find.text(replace ? 'Remote author' : 'My author'), findsOneWidget);
      expect(tester.widget<BookCover>(find.byType(BookCover)).reference,
          replace ? remoteResult.coverUrl : '/temporary/local.jpg');
      expect(repository.savedTitle, isNull);
      expect(find.text('080442957X'), findsOneWidget);
    });
  }

  testWidgets(
      'selection fills empty fields; work ISBN stays blank and values remain editable',
      (tester) async {
    await size(tester);
    final service = SearchService()..response = (_) async => resultPage;
    final repository = Repository();
    await tester.pumpWidget(MaterialApp(
        home: AddBookScreen(repository: repository, isbnService: service)));
    await tester.tap(find.text('Szukaj książki po tytule lub autorze'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'T');
    await search(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wybierz książkę'));
    await tester.pumpAndSettle();
    expect(find.text('Remote title'), findsOneWidget);
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(2))
            .controller!
            .text,
        isEmpty);
    expect(repository.savedTitle, isNull);
    await tester.enterText(find.byType(TextFormField).at(0), 'Corrected title');
    final save = find.widgetWithText(FilledButton, 'Zapisz książkę');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(repository.savedTitle, 'Corrected title');
    expect(repository.savedAuthor, 'Remote author');
  });
}
