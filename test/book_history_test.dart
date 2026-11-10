import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/data/library_database.dart';
import 'package:my_library/data/library_repository.dart';
import 'package:my_library/main.dart';
import 'package:my_library/models/book.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late LibraryRepository repository;
  late Database db;
  late Book book;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    final database = LibraryDatabase.inMemory(databaseFactoryFfi);
    db = await database.database;
    repository = LibraryRepository(database: database);
    book = await repository.addBook(title: 'Current', author: 'Author');
    final other = await repository.addBook(title: 'Other', author: 'Author');
    await db.delete('history');
    for (final entry in [
      HistoryEntry(
          id: 'old',
          bookId: book.id,
          bookTitle: book.title,
          action: 'added',
          timestamp: DateTime(2020, 1, 1, 10, 5)),
      HistoryEntry(
          id: 'foreign',
          bookId: other.id,
          bookTitle: other.title,
          action: 'given',
          detail: 'OTHER BOOK ONLY',
          timestamp: DateTime(2025)),
      HistoryEntry(
          id: 'new',
          bookId: book.id,
          bookTitle: book.title,
          action: 'borrowed',
          detail: 'Wypożyczono: Anna',
          timestamp: DateTime(2021, 2, 3, 14, 6)),
    ]) {
      await db.insert('history', entry.toMap());
    }
  });
  tearDown(() async => db.close());

  test(
      'query filters by ID, orders newest first, preserves global history and writes nothing',
      () async {
    final before = await db.query('history');
    expect((await repository.historyForBook(book.id)).map((e) => e.id),
        ['new', 'old']);
    expect(await repository.historyForBook('missing'), isEmpty);
    expect((await repository.history()).map((e) => e.id),
        ['foreign', 'new', 'old']);
    expect(await db.query('history'), before);
  });

  test('history query is bounded and uses book timestamp index', () async {
    for (var i = 0; i < 70; i++) {
      await db.insert(
          'history',
          HistoryEntry(
            id: 'event-$i',
            bookId: book.id,
            bookTitle: book.title,
            action: 'returned',
            timestamp: DateTime(2030, 1, 1).add(Duration(minutes: i)),
          ).toMap());
    }
    final result = await repository.historyForBook(book.id);
    expect(result, hasLength(LibraryRepository.bookHistoryLimit));
    expect(result.first.id, 'event-69');
    expect(result.last.id, 'event-20');
    final plan = await db.rawQuery(
        'EXPLAIN QUERY PLAN SELECT * FROM history WHERE book_id = ? ORDER BY timestamp DESC, id DESC LIMIT 50',
        [book.id]);
    expect(plan.toString(), contains('idx_history_book_timestamp'));
  });

  testWidgets(
      'details shows only current book events in order with Polish labels and date/time',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final before = await tester.runAsync(() => db.query('history'));
    await tester.pumpWidget(MaterialApp(
        home: BookDetailsScreen(book: book, repository: repository)));
    await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.text('Historia książki'), findsOneWidget);
    expect(find.text('Wypożyczono'), findsOneWidget);
    expect(find.text('Dodano na półkę'), findsOneWidget);
    expect(find.textContaining('03.02.2021 · 14:06'), findsOneWidget);
    expect(find.textContaining('Wypożyczono: Anna'), findsOneWidget);
    expect(find.textContaining('OTHER BOOK ONLY'), findsNothing);
    expect(tester.getTopLeft(find.text('Wypożyczono')).dy,
        lessThan(tester.getTopLeft(find.text('Dodano na półkę')).dy));
    expect(await tester.runAsync(() => db.query('history')), before);
  });

  testWidgets('details has useful empty history state', (tester) async {
    await tester.runAsync(
        () => db.delete('history', where: 'book_id = ?', whereArgs: [book.id]));
    await tester.pumpWidget(MaterialApp(
        home: BookDetailsScreen(book: book, repository: repository)));
    await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Brak zapisanych zdarzeń dla tej książki'),
        findsOneWidget);
  });
}
