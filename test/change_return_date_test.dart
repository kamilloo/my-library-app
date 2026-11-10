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

  for (final day in [30, 15]) {
    test(
        'change to day $day preserves identity loan metadata and prior history',
        () async {
      final historyBefore = await db.query('history');
      final result = await repository.updateReturnDate(
          original.id, DateTime(2026, 11, day, 18));
      expect(result.returnDate, DateTime(2026, 11, day));
      final saved = (await db.query('books')).single;
      for (final entry in original.toMap().entries) {
        if (!['return_date', 'updated_at'].contains(entry.key)) {
          expect(saved[entry.key], entry.value, reason: entry.key);
        }
      }
      expect(result.updatedAt, now);
      expect(
          await db.query('history',
              where: 'action != ?', whereArgs: ['return_date_changed']),
          historyBefore);
      final event = (await db.query('history',
              where: 'action = ?', whereArgs: ['return_date_changed']))
          .single;
      expect(event['book_id'], original.id);
      expect(event['detail'],
          'Zmieniono termin zwrotu: 20.11.2026 → $day.11.2026');
      expect(event['timestamp'], now.toIso8601String());
    });
  }

  test('add first date and remove date record explicit old/new values',
      () async {
    await db.update('books', {'return_date': null});
    await repository.updateReturnDate(original.id, DateTime(2026, 11, 25));
    await repository.updateReturnDate(original.id, null);
    final events = await db.query('history',
        where: 'action = ?', whereArgs: ['return_date_changed']);
    expect(events.map((row) => row['detail']), [
      'Zmieniono termin zwrotu: Nie ustawiono terminu zwrotu → 25.11.2026',
      'Zmieniono termin zwrotu: 25.11.2026 → Nie ustawiono terminu zwrotu',
    ]);
    expect((await db.query('books')).single['return_date'], isNull);
  });

  test('same calendar day and absent-to-absent changes are no-ops', () async {
    final before = await db.query('books');
    final historyBefore = await db.query('history');
    await repository.updateReturnDate(original.id, DateTime(2026, 11, 20, 22));
    expect(await db.query('books'), before);
    expect(await db.query('history'), historyBefore);
    await repository.updateReturnDate(original.id, null);
    final cleared = await db.query('books');
    final clearedHistory = await db.query('history');
    await repository.updateReturnDate(original.id, null);
    expect(await db.query('books'), cleared);
    expect(await db.query('history'), clearedHistory);
  });

  test('past date rejected with Polish validation; today accepted', () async {
    final before = await db.query('books');
    await expectLater(
        repository.updateReturnDate(original.id, DateTime(2026, 11, 9)),
        throwsA(isA<ReturnDateException>().having((e) => e.message, 'message',
            'Termin zwrotu nie może być w przeszłości.')));
    expect(await db.query('books'), before);
    expect(await db.query('history'), hasLength(2));
    await repository.updateReturnDate(original.id, DateTime(2026, 11, 10));
    expect((await db.query('books')).single['return_date'],
        DateTime(2026, 11, 10).toIso8601String());
  });

  for (final status in [BookStatus.available, BookStatus.given]) {
    test('reject editing a ${status.name} book without history', () async {
      await db.update('books', {'status': status.name});
      final before = await db.query('books');
      await expectLater(repository.updateReturnDate(original.id, null),
          throwsA(isA<ReturnDateException>()));
      expect(await db.query('books'), before);
      expect(await db.query('history'), hasLength(2));
    });
  }

  test('reject missing book without history', () async {
    await expectLater(
        repository.updateReturnDate('missing', DateTime(2026, 11, 30)),
        throwsA(isA<ReturnDateException>()));
    expect(await db.query('history'), hasLength(2));
  });

  test(
      'history insertion failure rolls back date and leaves reminders untouched',
      () async {
    await reminders.setEnabled(original.id, true);
    notifications.schedules.clear();
    notifications.cancellations.clear();
    final before = await db.query('books');
    final historyBefore = await db.query('history');
    await db.execute("""
      CREATE TRIGGER fail_return_date_history BEFORE INSERT ON history
      WHEN NEW.action = 'return_date_changed'
      BEGIN SELECT RAISE(ABORT, 'history failure'); END
    """);
    await expectLater(
        repository.updateReturnDate(original.id, DateTime(2026, 11, 30)),
        throwsA(isA<DatabaseException>()));
    expect(await db.query('books'), before);
    expect(await db.query('history'), historyBefore);
    expect(notifications.schedules, isEmpty);
    expect(notifications.cancellations, isEmpty);
  });

  test(
      'reminder reschedules cancels on clear and preserves opt-in for later date',
      () async {
    await reminders.setEnabled(original.id, true);
    final id = notifications.pending.keys.single;
    await repository.updateReturnDate(original.id, DateTime(2026, 11, 30));
    expect(notifications.pending.keys, [id]);
    expect(notifications.pending[id]!.day, 30);
    await repository.updateReturnDate(original.id, null);
    expect(notifications.pending, isEmpty);
    expect(await reminders.enabled(original.id), isTrue);
    await repository.updateReturnDate(original.id, DateTime(2026, 12, 1));
    expect(notifications.pending.keys, [id]);
    await repository.updateReturnDate(original.id, DateTime(2026, 11, 10));
    expect(notifications.pending, isEmpty);
    expect(await reminders.enabled(original.id), isTrue);
    expect(notifications.permissionRequests, 1);
  });

  test('notification failure does not undo committed date and history',
      () async {
    await reminders.setEnabled(original.id, true);
    notifications.fail = true;
    final result =
        await repository.updateReturnDate(original.id, DateTime(2026, 11, 30));
    expect(result.returnDate, DateTime(2026, 11, 30));
    expect((await db.query('books')).single['return_date'],
        result.returnDate!.toIso8601String());
    expect(await db.query('history'), hasLength(3));
    expect(await reminders.enabled(original.id), isTrue);
    notifications.fail = false;
    await reminders.reconcile();
    expect(notifications.pending.values.single.day, 30);
  });
}
