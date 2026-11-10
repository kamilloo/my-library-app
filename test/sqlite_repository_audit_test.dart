import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/data/library_database.dart';
import 'package:my_library/data/library_repository.dart';
import 'package:my_library/models/book.dart';
import 'package:my_library/models/return_date.dart';
import 'package:my_library/services/return_reminders.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'return_reminders_test.dart' show FakeNotifications;

void main() {
  late LibraryDatabase database;
  late Database db;
  late LibraryRepository repository;
  late ReturnReminders reminders;
  late FakeNotifications notifications;
  var tick = 0;
  DateTime clock() => DateTime(2026, 11, 10, 12).add(Duration(seconds: tick++));
  setUpAll(() {
    sqfliteFfiInit();
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/Warsaw'));
  });
  setUp(() async {
    tick = 0;
    database = LibraryDatabase.inMemory(databaseFactoryFfi);
    db = await database.database;
    notifications = FakeNotifications();
    reminders = ReturnReminders(database, notifications, now: clock);
    repository = LibraryRepository(
        database: database, reminders: reminders, clock: clock);
  });
  tearDown(() async => db.close());

  Future<Book> add({String? isbn}) => repository.addBook(
      title: 'Tytuł',
      author: 'Autor',
      description: 'Opis zachowany',
      barcode: isbn,
      coverUrl: 'https://example.com/cover.jpg',
      condition: 'Nowa',
      directory: 'Istniejąca półka');
  Future<Book> current(String id) async => Book.fromMap(
      (await db.query('books', where: 'id = ?', whereArgs: [id])).single);
  Future<List<Map<String, Object?>>> history() =>
      db.query('history', orderBy: 'id');
  Future<List<List<Map<String, Object?>>>> snapshot() async => [
        await db.query('books', orderBy: 'id'),
        await history(),
        await db.query('return_reminders', orderBy: 'id'),
      ];

  test(
      'empty collection reads never seed records, including after final deletion',
      () async {
    expect(await repository.books(), isEmpty);
    final book = await add();
    await repository.deleteBook(book.id);
    expect(await repository.books(), isEmpty);
    expect(await history(), isEmpty);
  });

  test('concurrent initialization shares one database instance', () async {
    final isolated = LibraryDatabase.inMemory(databaseFactoryFfi);
    final handles =
        await Future.wait(List.generate(3, (_) => isolated.database));
    try {
      expect(
          handles.every((handle) => identical(handle, handles.first)), isTrue);
    } finally {
      for (final handle in handles.toSet()) {
        if (handle.isOpen) await handle.close();
      }
    }
  });

  test(
      'stale snapshots cannot overwrite metadata or newer due dates during loan writes',
      () async {
    final stale = await add();
    await repository.updateBook(
        id: stale.id,
        title: 'Poprawiony tytuł',
        author: 'Poprawiony autor',
        barcode: '080442957X',
        condition: 'Zużyta');
    await repository.lendBook(stale, 'Anna', DateTime(2026, 11, 20));
    final firstLoan = await current(stale.id);
    expect(firstLoan.title, 'Poprawiony tytuł');
    expect(firstLoan.barcode, '080442957X');
    await repository.updateReturnDate(stale.id, DateTime(2026, 12, 1));
    await repository.updateBook(
        id: stale.id,
        title: 'Najnowszy tytuł',
        author: 'Najnowszy autor',
        barcode: '080442957X',
        condition: 'Dobry');
    await repository.returnBook(firstLoan);
    final returned = await current(stale.id);
    expect(returned.title, 'Najnowszy tytuł');
    expect(returned.author, 'Najnowszy autor');
    expect(returned.description, stale.description);
    expect(returned.coverUrl, stale.coverUrl);
    expect(returned.returnDate, isNull);
    expect(
        (await history())
            .singleWhere((e) => e['action'] == 'returned')['book_title'],
        'Najnowszy tytuł');
  });

  test(
      'full lifecycle preserves identity/metadata, records once, and resets reminders on reborrow',
      () async {
    final book = await add(isbn: '0-8044-2957-x');
    final metadata = book.toMap()
      ..removeWhere((key, _) => [
            'status',
            'borrowed_by',
            'borrowed_date',
            'return_date',
            'updated_at',
          ].contains(key));
    expect((await current(book.id)).status, BookStatus.available);
    await repository.lendBook(book, ' Anna ', null);
    final borrowed = await current(book.id);
    expect(borrowed.borrowedBy, 'Anna');
    final borrowingDate = borrowed.borrowedDate;
    expect(borrowingDate, isNotNull);
    expect(await reminders.enabled(book.id), isFalse);
    await repository.updateReturnDate(book.id, DateTime(2026, 11, 20));
    await reminders.setEnabled(book.id, true);
    final notificationId = notifications.pending.keys.single;
    for (final day in [15, 25]) {
      await repository.updateReturnDate(book.id, DateTime(2026, 11, day));
      final saved = await current(book.id);
      expect(saved.borrowedDate, borrowingDate);
      expect(saved.borrowedBy, 'Anna');
      expect(saved.status, BookStatus.borrowed);
      expect(notifications.pending.keys, [notificationId]);
    }
    await repository.updateReturnDate(book.id, null);
    expect(notifications.pending, isEmpty);
    expect(await reminders.enabled(book.id), isTrue);
    await repository.updateReturnDate(book.id, DateTime(2026, 11, 20));
    await repository.extendLoan(book.id, DateTime(2026, 12, 4));
    expect(notifications.pending[notificationId]!.day, 4);
    expect((await current(book.id)).borrowedDate, borrowingDate);
    await repository.returnBook(borrowed);
    final returned = await current(book.id);
    expect(returned.status, BookStatus.available);
    expect(returned.borrowedBy, isNull);
    expect(returned.borrowedDate, isNull);
    expect(returned.returnDate, isNull);
    expect(notifications.pending, isEmpty);
    await repository.lendBook(returned, 'Jan', DateTime(2026, 12, 10));
    final second = await current(book.id);
    expect(second.borrowedBy, 'Jan');
    expect(second.borrowedDate!.isAfter(borrowingDate!), isTrue);
    expect(await reminders.enabled(book.id), isFalse);
    expect(notifications.pending, isEmpty);
    final after = second.toMap()
      ..removeWhere((key, _) => [
            'status',
            'borrowed_by',
            'borrowed_date',
            'return_date',
            'updated_at',
          ].contains(key));
    expect(after, metadata);
    final events = await history();
    expect(events.every((event) => event['book_id'] == book.id), isTrue);
    expect(
        events.where((event) => event['action'] == 'borrowed'), hasLength(2));
    expect(events.where((event) => event['action'] == 'loan_extended'),
        hasLength(1));
    expect(events.where((event) => event['action'] == 'return_date_changed'),
        hasLength(5));
  });

  test('invalid and repeated transitions append no history', () async {
    final book = await add();
    final initial = await snapshot();
    await expectLater(repository.returnBook(book), throwsStateError);
    await expectLater(
        repository.lendBook(book, ' ', DateTime(2027)), throwsArgumentError);
    expect(await snapshot(), initial);
    await repository.lendBook(book, 'Anna', DateTime(2026, 11, 20));
    final borrowed = await current(book.id);
    final before = await snapshot();
    await expectLater(
        repository.lendBook(book, 'Other', DateTime(2027)), throwsStateError);
    expect(await snapshot(), before);
    await repository.giveBook(borrowed, 'Anna');
    final given = await current(book.id);
    expect(given.status, BookStatus.given);
    expect(given.returnDate, isNull);
    final finalState = await snapshot();
    await expectLater(repository.giveBook(given, 'Anna'), throwsStateError);
    await expectLater(repository.returnBook(given), throwsStateError);
    await expectLater(
        repository.lendBook(given, 'Jan', null), throwsStateError);
    expect(await snapshot(), finalState);
  });

  test('stale prior-loan return cannot end a new borrower loan', () async {
    final book = await add();
    await repository.lendBook(book, 'Anna', DateTime(2026, 11, 20));
    final oldLoan = await current(book.id);
    await repository.returnBook(oldLoan);
    await repository.lendBook(book, 'Jan', DateTime(2026, 12, 10));
    final before = await snapshot();
    await expectLater(repository.returnBook(oldLoan), throwsStateError);
    expect(await snapshot(), before);
  });

  for (final operation in ['borrowed', 'returned', 'given']) {
    test(
        '$operation history failure rolls back loan fields and reminder preference',
        () async {
      final book = await add();
      if (operation != 'borrowed') {
        await repository.lendBook(book, 'Anna', DateTime(2026, 11, 20));
        await reminders.setEnabled(book.id, true);
      }
      final before = await snapshot();
      notifications.schedules.clear();
      notifications.cancellations.clear();
      await db.execute("""
        CREATE TRIGGER reject_history BEFORE INSERT ON history
        WHEN NEW.action = '$operation'
        BEGIN SELECT RAISE(ABORT, 'history failure'); END
      """);
      final active = await current(book.id);
      final action = switch (operation) {
        'borrowed' =>
          repository.lendBook(active, 'Anna', DateTime(2026, 11, 20)),
        'returned' => repository.returnBook(active),
        _ => repository.giveBook(active, 'Anna'),
      };
      await expectLater(action, throwsA(isA<DatabaseException>()));
      expect(await snapshot(), before);
      expect(notifications.schedules, isEmpty);
      expect(notifications.cancellations, isEmpty);
    });
  }

  test(
      'concurrent normalized ISBN saves have one winner and one Polish duplicate error',
      () async {
    final results = await Future.wait([
      for (final isbn in ['0-8044-2957-x', '080442957X'])
        add(isbn: isbn).then<Object>((book) => book, onError: (Object e) => e),
    ]);
    expect(results.whereType<Book>(), hasLength(1));
    expect(results.whereType<DuplicateIsbnException>(), hasLength(1));
    expect(results.whereType<DuplicateIsbnException>().single.toString(),
        DuplicateIsbnException.message);
    expect(await db.query('books'), hasLength(1));
    expect(await history(), hasLength(1));
  });

  test(
      'equivalent ISBN-10 and ISBN-13 cannot bypass duplicate checks concurrently',
      () async {
    final results = await Future.wait([
      for (final isbn in ['080442957X', '9780804429573'])
        add(isbn: isbn).then<Object>((book) => book, onError: (Object e) => e),
    ]);
    expect(results.whereType<Book>(), hasLength(1));
    expect(results.whereType<DuplicateIsbnException>(), hasLength(1));
    expect(await history(), hasLength(1));
  });

  test('equivalent ISBN edits exclude self but reject another book identity',
      () async {
    final first = await add(isbn: '080442957X');
    await repository.updateBook(
        id: first.id,
        title: first.title,
        author: first.author,
        barcode: '9780804429573',
        condition: first.condition);
    final second = await add(isbn: '9780525559474');
    final before = await snapshot();
    await expectLater(
        repository.updateBook(
            id: second.id,
            title: 'Changed',
            author: second.author,
            barcode: '0-8044-2957-x',
            condition: second.condition),
        throwsA(isA<DuplicateIsbnException>()));
    expect(await snapshot(), before);
  });

  test('parallel repeated return-date writes append exactly one actual change',
      () async {
    final book = await add();
    await repository.lendBook(book, 'Anna', DateTime(2026, 11, 20));
    await Future.wait(List.generate(
        3, (_) => repository.updateReturnDate(book.id, DateTime(2026, 12, 1))));
    expect((await history()).where((e) => e['action'] == 'return_date_changed'),
        hasLength(1));
  });

  test('deleted books cannot be resurrected by stale edit or loan operations',
      () async {
    final book = await add();
    await repository.deleteBook(book.id);
    await expectLater(
        repository.lendBook(book, 'Anna', DateTime(2027)), throwsStateError);
    await expectLater(
        repository.updateBook(
            id: book.id, title: 'Stale', author: 'A', condition: 'Nowa'),
        throwsStateError);
    expect(await db.query('books'), isEmpty);
    expect(await history(), isEmpty);
  });

  test('book update trigger failure leaves metadata and history untouched',
      () async {
    final book = await add();
    final before = await snapshot();
    await db.execute(
        "CREATE TRIGGER reject_update BEFORE UPDATE ON books BEGIN SELECT RAISE(ABORT, 'update failure'); END");
    await expectLater(repository.lendBook(book, 'Anna', DateTime(2027)),
        throwsA(isA<DatabaseException>()));
    expect(await snapshot(), before);
  });

  test(
      'reminder preference update failure leaves previous intent and pending request intact',
      () async {
    final book = await add();
    await repository.lendBook(book, 'Anna', DateTime(2026, 11, 20));
    await reminders.setEnabled(book.id, true);
    final before = await snapshot();
    final pending = Map.of(notifications.pending);
    await db.execute(
        "CREATE TRIGGER reject_preference BEFORE UPDATE ON return_reminders BEGIN SELECT RAISE(ABORT, 'preference failure'); END");
    expect(await reminders.setEnabled(book.id, false), ReminderResult.failed);
    expect(await snapshot(), before);
    expect(notifications.pending, pending);
  });

  test('queued deletion and due-date write leave no book or orphan history',
      () async {
    final book = await add();
    await repository.lendBook(book, 'Anna', DateTime(2026, 11, 20));
    await reminders.setEnabled(book.id, true);
    final operations = [
      repository.deleteBook(book.id),
      repository.updateReturnDate(book.id, DateTime(2026, 12, 1)),
    ];
    final results = await Future.wait([
      for (final op in operations)
        op.then<Object?>((_) => null, onError: (Object e) => e),
    ]);
    expect(results.every((e) => e == null || e is ReturnDateException), isTrue);
    expect(await db.query('books'), isEmpty);
    expect(await history(), isEmpty);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    expect(await reminders.enabled(book.id), isFalse);
    expect(notifications.pending, isEmpty);
  });
}
