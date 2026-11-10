import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/data/library_repository.dart';
import 'package:my_library/main.dart';
import 'package:my_library/services/open_library_service.dart';
import 'package:my_library/screens/book_cover.dart';
import 'cover_form_test.dart' show Picker, Repository;

class LookupService extends OpenLibraryService {
  final calls = <String>[];
  Future<OpenLibraryBook?> Function() response = () async => null;

  @override
  Future<OpenLibraryBook?> lookupByIsbn(String isbn) {
    calls.add(isbn);
    return response();
  }
}

void main() {
  Future<void> open(WidgetTester tester, LookupService service,
      {Repository? repository, Picker? picker}) async {
    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: AddBookScreen(
        repository: repository ?? LibraryRepository(),
        coverPicker: picker,
        isbnService: service,
      ),
    ));
  }

  Future<void> lookup(WidgetTester tester) async {
    final button = find.text('Pobierz dane z ISBN');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
  }

  testWidgets('invalid ISBN makes no network request', (tester) async {
    final service = LookupService();
    await open(tester, service);
    await tester.enterText(find.byType(TextFormField).at(2), '978123');
    await lookup(tester);
    expect(service.calls, isEmpty);
    expect(find.text('Wpisz poprawny ISBN-10 lub ISBN-13.'), findsOneWidget);
  });

  testWidgets('normalized lookup fills metadata and preserves populated fields',
      (tester) async {
    final service = LookupService();
    final pending = Completer<OpenLibraryBook?>();
    service.response = () => pending.future;
    await open(tester, service);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(2), '978-0-525-55947-4');
    await lookup(tester);
    expect(find.text('Pobieranie danych…'), findsOneWidget);
    await tester.enterText(fields.at(0), 'Mój tytuł');
    pending.complete(const OpenLibraryBook(
      title: 'Returned title',
      author: 'Returned author',
    ));
    await tester.pumpAndSettle();
    expect(service.calls, ['9780525559474']);
    expect(find.text('Mój tytuł'), findsOneWidget);
    expect(find.text('Returned title'), findsNothing);
    expect(find.text('Returned author'), findsOneWidget);
  });

  testWidgets('no match, offline and timeout preserve input and allow retry',
      (tester) async {
    final service = LookupService();
    await open(tester, service);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Ręczny tytuł');
    await tester.enterText(fields.at(2), '080442957X');
    await lookup(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('Nie znaleziono książki'), findsOneWidget);
    for (final error in [Exception('offline'), TimeoutException('timeout')]) {
      service.response = () async => throw error;
      await tester.tap(find.text('Spróbuj ponownie'));
      await tester.pumpAndSettle();
      expect(find.text('Ręczny tytuł'), findsOneWidget);
      expect(find.text('080442957X'), findsOneWidget);
    }
    expect(find.textContaining('Przekroczono czas'), findsOneWidget);
    service.response =
        () async => const OpenLibraryBook(title: 'T', author: 'A');
    await tester.tap(find.text('Spróbuj ponownie'));
    await tester.pumpAndSettle();
    expect(find.text('Ręczny tytuł'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('changed ISBN ignores pending metadata', (tester) async {
    final service = LookupService();
    final pending = Completer<OpenLibraryBook?>();
    service.response = () => pending.future;
    await open(tester, service);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(2), '080442957X');
    await lookup(tester);
    await tester.enterText(fields.at(2), '9780525559474');
    pending.complete(const OpenLibraryBook(title: 'Stale', author: 'Stale'));
    await tester.pumpAndSettle();
    expect(find.text('Stale'), findsNothing);
  });

  for (final value in ['', '9780525559475']) {
    testWidgets('empty or invalid checksum ISBN rejected: "$value"',
        (tester) async {
      final service = LookupService();
      await open(tester, service);
      await tester.enterText(find.byType(TextFormField).at(2), value);
      await lookup(tester);
      expect(service.calls, isEmpty);
      expect(find.text('Wpisz poprawny ISBN-10 lub ISBN-13.'), findsOneWidget);
    });
  }

  for (final entry in {
    '0-8044-2957-x': '080442957X',
    '978-0-525-55947-4': '9780525559474',
  }.entries) {
    testWidgets('successful normalized lookup: ${entry.key}', (tester) async {
      final service = LookupService()
        ..response = () async => const OpenLibraryBook(
            title: 'Found title',
            author: 'Found author',
            coverUrl: 'https://example.com/cover.jpg');
      await open(tester, service);
      await tester.enterText(find.byType(TextFormField).at(2), entry.key);
      await lookup(tester);
      await tester.pumpAndSettle();
      expect(service.calls, [entry.value]);
      expect(find.text('Found title'), findsOneWidget);
      expect(find.text('Found author'), findsOneWidget);
      expect(tester.widget<BookCover>(find.byType(BookCover)).reference,
          'https://example.com/cover.jpg');
    });
  }

  testWidgets('existing title author and selected local cover survive lookup',
      (tester) async {
    final service = LookupService()
      ..response = () async => const OpenLibraryBook(
          title: 'Remote title',
          author: 'Remote author',
          coverUrl: 'https://example.com/remote.jpg');
    final picker = Picker()..result = '/temporary/local.jpg';
    await open(tester, service, picker: picker);
    await tester.tap(find.text('Wybierz zdjęcie z urządzenia'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Local title');
    await tester.enterText(fields.at(1), 'Local author');
    await tester.enterText(fields.at(2), '080442957X');
    await lookup(tester);
    await tester.pumpAndSettle();
    expect(find.text('Local title'), findsOneWidget);
    expect(find.text('Local author'), findsOneWidget);
    expect(tester.widget<BookCover>(find.byType(BookCover)).reference,
        '/temporary/local.jpg');
    expect(picker.releases.last, '/temporary/local.jpg');
  });

  testWidgets('repeated taps while pending start only one request',
      (tester) async {
    final service = LookupService();
    final pending = Completer<OpenLibraryBook?>();
    service.response = () => pending.future;
    await open(tester, service);
    await tester.enterText(find.byType(TextFormField).at(2), '080442957X');
    await lookup(tester);
    await lookup(tester);
    expect(service.calls, ['080442957X']);
    pending.complete(null);
    await tester.pumpAndSettle();
  });

  testWidgets('manual save succeeds after offline lookup', (tester) async {
    final service = LookupService()
      ..response = () async => throw Exception('offline');
    final repository = Repository();
    await open(tester, service, repository: repository);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Manual title');
    await tester.enterText(fields.at(1), 'Manual author');
    await tester.enterText(fields.at(2), '080442957X');
    await lookup(tester);
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Sprawdź połączenie z internetem'), findsOneWidget);
    final save = find.widgetWithText(FilledButton, 'Zapisz książkę');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(repository.savedTitle, 'Manual title');
    expect(repository.savedAuthor, 'Manual author');
    expect(repository.savedBarcode, '080442957X');
    expect(tester.takeException(), isNull);
  });
}
