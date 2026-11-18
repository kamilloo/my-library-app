import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/data/library_database.dart';
import 'package:my_library/data/library_repository.dart';
import 'package:my_library/main.dart';
import 'package:my_library/models/book.dart';
import 'package:my_library/screens/book_history_section.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late _TrackingRepository repository;
  late Database db;
  late Book book;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    final database = LibraryDatabase.inMemory(databaseFactoryFfi);
    db = await database.database;
    repository = _TrackingRepository(database);
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
    expect(
        (await repository.historyForBook(book.id, limit: 5)).map((e) => e.id),
        ['new', 'old']);
    expect(await repository.historyForBook('missing', limit: 5), isEmpty);
    expect((await repository.history()).map((e) => e.id),
        ['foreign', 'new', 'old']);
    expect(await db.query('history'), before);
  });

  Future<void> seedHistory(int count) async {
    await db.delete('history', where: 'book_id = ?', whereArgs: [book.id]);
    final batch = db.batch();
    for (var i = 0; i < count; i++) {
      final number = i.toString().padLeft(2, '0');
      batch.insert(
        'history',
        HistoryEntry(
          id: 'event-$number',
          bookId: book.id,
          bookTitle: book.title,
          action: 'added',
          detail: 'Event $number',
          timestamp: DateTime(2020),
        ).toMap(),
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> settleHistory(WidgetTester tester) async {
    await tester.runAsync(() async => repository.pendingHistory);
    await tester.pumpAndSettle();
  }

  for (final count in [0, 1, 5, 6, 15, 17, 61]) {
    testWidgets('paginates $count tied events on a small screen',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(() => seedHistory(count));
      final before = await tester.runAsync(() => db.query('history'));
      await tester.pumpWidget(MaterialApp(
          home: BookDetailsScreen(book: book, repository: repository)));
      await tester.scrollUntilVisible(find.text('Historia książki'), 150);
      await settleHistory(tester);

      final section = find.byType(BookHistorySection);
      final more = find.text('Pokaż więcej');
      final tiles =
          find.descendant(of: section, matching: find.byType(ListTile));
      int shown = count < 5 ? count : 5;
      final expectedLimits = [6];
      while (true) {
        final details = tester
            .widgetList<ListTile>(tiles)
            .map((tile) => (tile.subtitle! as Text).data!.split('\n').first);
        expect(details, [
          for (var i = count - 1; i >= count - shown; i--)
            'Event ${i.toString().padLeft(2, '0')}',
        ]);
        expect(tester.takeException(), isNull);
        if (shown == count) {
          expect(more, findsNothing);
          break;
        }
        expect(more, findsOneWidget);
        await tester.scrollUntilVisible(more.hitTestable(), 240);
        await tester.tap(more);
        await settleHistory(tester);
        shown = shown + 10 < count ? shown + 10 : count;
        expectedLimits.add(11);
      }
      expect(repository.historyLimits, expectedLimits);
      expect(await tester.runAsync(() => db.query('history')), before);
    });
  }

  testWidgets('return action precedes history and resets the expanded list',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      await seedHistory(16);
      await repository.lendBook(book, 'Anna', null);
      book = (await repository.books()).firstWhere((b) => b.id == book.id);
    });
    await tester.pumpWidget(MaterialApp(
        home: BookDetailsScreen(book: book, repository: repository)));
    await settleHistory(tester);

    final returnAction = find.text('Oznacz jako zwróconą');
    final history = find.text('Historia książki');
    expect(tester.getTopLeft(returnAction).dy,
        lessThan(tester.getTopLeft(history).dy));
    expect(tester.getTopLeft(history).dy,
        lessThan(tester.getTopLeft(find.text('Usuń książkę')).dy));

    final more = find.text('Pokaż więcej');
    await tester.ensureVisible(more);
    await tester.tap(more);
    await settleHistory(tester);
    final tiles = find.descendant(
        of: find.byType(BookHistorySection), matching: find.byType(ListTile));
    expect(tiles, findsNWidgets(15));

    await tester.ensureVisible(returnAction);
    await tester.runAsync(() async {
      await tester.tap(returnAction);
      await repository.pendingReturn;
    });
    await tester.pump();
    await settleHistory(tester);
    expect(tiles, findsNWidgets(5));
    expect(
        (tester.widget<ListTile>(tiles.first).title! as Text).data, 'Zwrócono');
    expect(more, findsOneWidget);
    expect(returnAction, findsNothing);
  });

  testWidgets(
      'details shows only current book events in order with Polish labels and date/time',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final before = await tester.runAsync(() => db.query('history'));
    await tester.pumpWidget(MaterialApp(
        home: BookDetailsScreen(book: book, repository: repository)));
    await tester.scrollUntilVisible(find.text('Historia książki'), 150);
    await settleHistory(tester);
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
    await tester.scrollUntilVisible(find.text('Historia książki'), 150);
    await settleHistory(tester);
    expect(find.textContaining('Brak zapisanych zdarzeń dla tej książki'),
        findsOneWidget);
  });
}

class _TrackingRepository extends LibraryRepository {
  _TrackingRepository(LibraryDatabase database) : super(database: database);

  final historyLimits = <int>[];
  Future<List<HistoryEntry>>? pendingHistory;
  late Future<void> pendingReturn;

  @override
  Future<List<HistoryEntry>> historyForBook(
    String bookId, {
    required int limit,
    String? beforeId,
  }) {
    historyLimits.add(limit);
    return pendingHistory =
        super.historyForBook(bookId, limit: limit, beforeId: beforeId);
  }

  @override
  Future<void> returnBook(Book book) => pendingReturn = super.returnBook(book);
}
