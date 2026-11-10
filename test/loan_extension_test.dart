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
  late Database db;
  late LibraryRepository repository;
  late ReturnReminders reminders;
  late FakeNotifications notifications;
  late Book original;
  final now = DateTime(2026, 11, 10, 12);
  setUpAll(() {
    sqfliteFfiInit();
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/Warsaw'));
  });
  setUp(() async {
    final database = LibraryDatabase.inMemory(databaseFactoryFfi);
    db = await database.database;
    notifications = FakeNotifications();
    reminders = ReturnReminders(database, notifications, now: () => now);
    repository = LibraryRepository(
        database: database, reminders: reminders, clock: () => now);
    original = Book(
      id: 'book',
      title: 'Title',
      author: 'Author',
      description: 'Description',
      coverUrl: 'covers/original.jpg',
      barcode: '080442957X',
      condition: 'Nowa',
      directory: 'Shelf',
      status: BookStatus.borrowed,
      borrowedBy: 'Anna',
      borrowedDate: DateTime(2026, 11, 1),
      returnDate: DateTime(2026, 11, 20),
      createdAt: DateTime(2025),
      updatedAt: DateTime(2026, 11, 1),
    );
    await db.insert('books', original.toMap());
    for (final action in ['added', 'borrowed']) {
      await db.insert(
          'history',
          HistoryEntry(
            id: action,
            bookId: original.id,
            bookTitle: original.title,
            action: action,
            detail: 'Original $action',
            timestamp: DateTime(2026, 11, 1),
          ).toMap());
    }
  });
  tearDown(() async => db.close());

  for (final days in [7, 14, 30]) {
    test('+$days days extends from saved date with exactly one distinct event',
        () async {
      final oldHistory = await db.query('history');
      final date = extendedReturnDate(original.returnDate!, days);
      final saved = await repository.extendLoan(original.id, date);
      expect(saved.returnDate, date);
      final row = (await db.query('books')).single;
      for (final entry in original.toMap().entries) {
        if (!['return_date', 'updated_at'].contains(entry.key)) {
          expect(row[entry.key], entry.value, reason: entry.key);
        }
      }
      expect(await db.query('history', where: "action != 'loan_extended'"),
          oldHistory);
      final events =
          await db.query('history', where: "action = 'loan_extended'");
      expect(events, hasLength(1));
      expect(events.single['detail'],
          'Przedłużono wypożyczenie: 20.11.2026 → ${formatReturnDate(date)}');
      expect(await db.query('history', where: "action = 'return_date_changed'"),
          isEmpty);
    });
  }

  test('custom later date and missing first date use extension history',
      () async {
    final chosen = DateTime(2027, 2, 3);
    expect(
        (await repository.extendLoan(original.id, chosen)).returnDate, chosen);
    await db.update('books', {'return_date': null});
    await repository.extendLoan(original.id, DateTime(2027, 3, 1));
    final rows = await db.query('history', where: "action = 'loan_extended'");
    expect(rows.last['detail'],
        'Przedłużono wypożyczenie: Nie ustawiono terminu zwrotu → 01.03.2027');
  });

  test('calendar presets handle month ends and leap years', () {
    expect(extendedReturnDate(DateTime(2026, 1, 31), 7), DateTime(2026, 2, 7));
    expect(extendedReturnDate(DateTime(2028, 2, 28), 7), DateTime(2028, 3, 6));
    expect(extendedReturnDate(DateTime(2027, 2, 28), 7), DateTime(2027, 3, 7));
    expect(
        extendedReturnDate(DateTime(2026, 12, 31), 30), DateTime(2027, 1, 30));
  });

  for (final month in [3, 10]) {
    test('calendar extension remains midnight across DST in month $month', () {
      final zone = tz.getLocation('Europe/Warsaw');
      final start = tz.TZDateTime(zone, 2026, month, month == 3 ? 28 : 24);
      final result = extendedReturnDate(start, 7);
      final zoned = tz.TZDateTime(zone, result.year, result.month, result.day);
      expect(result.hour, 0);
      expect(zoned.hour, 0);
      expect(zoned.difference(start).inHours, month == 3 ? 167 : 169);
    });
  }

  test('overdue loan can extend into future from the original due date',
      () async {
    await db.update(
        'books', {'return_date': DateTime(2026, 11, 1).toIso8601String()});
    final newDate = extendedReturnDate(DateTime(2026, 11, 1), 14);
    expect((await repository.extendLoan(original.id, newDate)).returnDate,
        DateTime(2026, 11, 15));
    expect((await db.query('books')).single['borrowed_date'],
        original.borrowedDate!.toIso8601String());
  });

  for (final date in [DateTime(2026, 11, 19), DateTime(2026, 11, 20)]) {
    test('reject earlier or unchanged date $date without modifying data',
        () async {
      final before = await db.query('books');
      await expectLater(repository.extendLoan(original.id, date),
          throwsA(isA<ReturnDateException>()));
      expect(await db.query('books'), before);
      expect(await db.query('history'), hasLength(2));
    });
  }

  test('overdue proposals including today are rejected with Polish feedback',
      () async {
    await db.update(
        'books', {'return_date': DateTime(2026, 11, 1).toIso8601String()});
    for (final day in [8, 10]) {
      await expectLater(
          repository.extendLoan(original.id, DateTime(2026, 11, day)),
          throwsA(isA<ReturnDateException>().having((e) => e.message, 'message',
              'Termin prolongaty musi przypadać po dzisiejszym dniu.')));
    }
    expect(await db.query('history'), hasLength(2));
  });

  for (final status in [BookStatus.available, BookStatus.given]) {
    test('reject extension for ${status.name}', () async {
      await db.update('books', {'status': status.name});
      await expectLater(repository.extendLoan(original.id, DateTime(2027)),
          throwsA(isA<ReturnDateException>()));
      expect(await db.query('history'), hasLength(2));
    });
  }

  test('missing or deleted book is rejected', () async {
    await repository.deleteBook(original.id);
    await expectLater(repository.extendLoan(original.id, DateTime(2027)),
        throwsA(isA<ReturnDateException>()));
    expect(await db.query('books'), isEmpty);
    expect(await db.query('history'), isEmpty);
  });

  test('concurrent same-target submissions append exactly one extension',
      () async {
    final results = await Future.wait([
      for (var i = 0; i < 2; i++)
        repository
            .extendLoan(original.id, DateTime(2026, 12, 4))
            .then((_) => true, onError: (_) => false),
    ]);
    expect(results.where((value) => value), hasLength(1));
    expect(await db.query('history', where: "action = 'loan_extended'"),
        hasLength(1));
    expect(
        await db.query('history', where: "action = 'borrowed'"), hasLength(1));
    expect(await db.query('history', where: "action = 'return_date_changed'"),
        isEmpty);
  });

  test('history failure rolls back date and does not touch notifications',
      () async {
    await reminders.setEnabled(original.id, true);
    notifications.schedules.clear();
    final before = await db.query('books');
    await db.execute("""
      CREATE TRIGGER fail_extension BEFORE INSERT ON history
      WHEN NEW.action = 'loan_extended'
      BEGIN SELECT RAISE(ABORT, 'history failure'); END
    """);
    await expectLater(repository.extendLoan(original.id, DateTime(2026, 12, 4)),
        throwsA(isA<DatabaseException>()));
    expect(await db.query('books'), before);
    expect(await db.query('history'), hasLength(2));
    expect(notifications.schedules, isEmpty);
  });

  test(
      'enabled reminder replaces same ID and failures cannot undo committed extension',
      () async {
    await reminders.setEnabled(original.id, true);
    final id = notifications.pending.keys.single;
    await repository.extendLoan(original.id, DateTime(2026, 12, 4));
    expect(notifications.pending.keys, [id]);
    expect(notifications.pending[id]!.day, 4);
    expect(notifications.pending[id]!.month, 12);
    notifications.fail = true;
    final saved =
        await repository.extendLoan(original.id, DateTime(2026, 12, 20));
    expect(saved.returnDate, DateTime(2026, 12, 20));
    expect(await db.query('history', where: "action = 'loan_extended'"),
        hasLength(2));
    expect(await reminders.enabled(original.id), isTrue);
    notifications.fail = false;
    await reminders.reconcile();
    expect(notifications.pending.keys, [id]);
    expect(notifications.pending[id]!.day, 20);
    expect(notifications.permissionRequests, 1);
  });
}
