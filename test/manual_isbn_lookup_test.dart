import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/data/library_repository.dart';
import 'package:my_library/main.dart';
import 'package:my_library/services/open_library_service.dart';

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
  Future<void> open(WidgetTester tester, LookupService service) async {
    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: AddBookScreen(
        repository: LibraryRepository(),
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
      description: 'Returned description',
    ));
    await tester.pumpAndSettle();
    expect(service.calls, ['9780525559474']);
    expect(find.text('Mój tytuł'), findsOneWidget);
    expect(find.text('Returned title'), findsNothing);
    expect(find.text('Returned author'), findsOneWidget);
    expect(find.text('Returned description'), findsOneWidget);
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
    service.response = () async => const OpenLibraryBook(title: 'T', author: 'A');
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
}
