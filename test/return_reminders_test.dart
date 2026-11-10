import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/data/library_database.dart';
import 'package:my_library/data/library_repository.dart';
import 'package:my_library/models/book.dart';
import 'package:my_library/services/return_reminders.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class FakeNotifications extends ReminderNotifications {
  bool allowed = true;
  bool fail = false;
  int permissionRequests = 0;
  final pending = <int, tz.TZDateTime>{};
  final cancellations = <int>[];
  final schedules = <int>[];
  final payloads = <int, String?>{};
  final failScheduleIds = <int>{};
  final failCancelIds = <int>{};
  @override
  Future<Map<int, String?>> pendingRequests() async =>
      {for (final id in pending.keys) id: payloads[id]};
  @override
  Future<void> prepare() async {}
  @override
  Future<bool> authorized({bool request = false}) async {
    if (request) permissionRequests++;
    return allowed;
  }

  @override
  Future<void> schedule(int id, Book book, tz.TZDateTime date) async {
    schedules.add(id);
    if (fail || failScheduleIds.contains(id)) {
      throw StateError('OS unavailable');
    }
    pending[id] = date;
    payloads[id] = reminderFingerprint(book, date);
  }

  @override
  Future<void> cancel(int id) async {
    cancellations.add(id);
    if (failCancelIds.contains(id)) throw StateError('Cannot cancel');
    pending.remove(id);
    payloads.remove(id);
  }
}

void main() {
  late LibraryDatabase database;
  late Database db;
  late FakeNotifications notifications;
  late ReturnReminders reminders;
  late LibraryRepository repository;
  late Book book;
  final now = DateTime.utc(2030, 1, 1);
  setUpAll(() {
    sqfliteFfiInit();
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/Warsaw'));
  });
  setUp(() async {
    database = LibraryDatabase.inMemory(databaseFactoryFfi);
    db = await database.database;
    notifications = FakeNotifications();
    reminders = ReturnReminders(database, notifications, now: () => now);
    repository = LibraryRepository(
        database: database, reminders: reminders, clock: () => now);
    book = await repository.addBook(title: 'Title', author: 'Author');
    await repository.lendBook(book, 'Anna', DateTime(2030, 6, 2));
    book = Book.fromMap((await db.query('books')).single);
  });
  tearDown(() async => db.close());

  test('decision requires borrowed status, opt-in, borrower and future date',
      () {
    final zone = tz.getLocation('Europe/Warsaw');
    expect(reminderDate(book, false, zone, now), isNull);
    expect(
        reminderDate(book.copyWith(status: BookStatus.given), true, zone, now),
        isNull);
    expect(
        reminderDate(book.copyWith(borrowedBy: ' '), true, zone, now), isNull);
    expect(
        reminderDate(book.copyWith(clearLoan: true), true, zone, now), isNull);
    expect(
        reminderDate(
            book.copyWith(returnDate: DateTime(2029)), true, zone, now),
        isNull);
    final date = reminderDate(book, true, zone, now)!;
    expect(date.hour, 9);
    expect(date.toUtc(), DateTime.utc(2030, 6, 2, 7));
    expect(reminderDate(book, true, zone, date), isNull);
    final winter = reminderDate(
        book.copyWith(returnDate: DateTime(2030, 1, 2)), true, zone, now)!;
    expect(winter.toUtc(), DateTime.utc(2030, 1, 2, 8));
  });

  test('default off, permission denial never schedules or enables', () async {
    expect(notifications.pending, isEmpty);
    expect(notifications.permissionRequests, 0);
    notifications.allowed = false;
    expect(await reminders.setEnabled(book.id, true), ReminderResult.denied);
    expect(await reminders.enabled(book.id), isFalse);
    expect(notifications.pending, isEmpty);
    expect(notifications.permissionRequests, 1);
    await reminders.reconcile();
    expect(notifications.permissionRequests, 1);
  });

  test('ineligible request does not ask permission', () async {
    await repository.updateReturnDate(book.id, null);
    expect(
        await reminders.setEnabled(book.id, true), ReminderResult.ineligible);
    expect(notifications.permissionRequests, 0);
  });

  test(
      'stable persisted ID replaces duplicates, survives manager restart and reschedules date',
      () async {
    expect(await reminders.setEnabled(book.id, true), ReminderResult.enabled);
    final id = notifications.pending.keys.single;
    await Future.wait(
        [reminders.setEnabled(book.id, true), reminders.reconcile()]);
    expect(notifications.pending.keys, [id]);
    final restarted = ReturnReminders(database, notifications, now: () => now);
    await restarted.reconcile();
    expect(notifications.pending.keys, [id]);
    expect(await restarted.enabled(book.id), isTrue);
    await repository.updateReturnDate(book.id, DateTime(2030, 7, 4));
    expect(notifications.pending.keys, [id]);
    expect(notifications.pending[id]!.month, 7);
    expect(notifications.pending[id]!.day, 4);
    await repository.updateReturnDate(book.id, null);
    expect(notifications.pending, isEmpty);
  });

  for (final action in ['returned', 'given', 'deleted', 'disabled']) {
    test('$action cancels notification and clears opt-in', () async {
      await reminders.setEnabled(book.id, true);
      final id = notifications.pending.keys.single;
      switch (action) {
        case 'returned':
          await repository.returnBook(book);
        case 'given':
          await repository.giveBook(book, 'Anna');
        case 'deleted':
          await repository.deleteBook(book.id);
        case 'disabled':
          await reminders.setEnabled(book.id, false);
      }
      expect(notifications.pending, isEmpty);
      expect(notifications.cancellations, contains(id));
      expect(await reminders.enabled(book.id), isFalse);
      await reminders.reconcile();
      expect(notifications.pending, isEmpty);
    });
  }

  test('expired date and permission revocation cancel without prompting',
      () async {
    await reminders.setEnabled(book.id, true);
    notifications.allowed = false;
    await reminders.reconcile();
    expect(notifications.pending, isEmpty);
    notifications.allowed = true;
    await ReturnReminders(database, notifications,
        now: () => DateTime.utc(2031)).reconcile();
    expect(notifications.pending, isEmpty);
    expect(notifications.permissionRequests, 1);
  });

  test('new loan does not inherit opt-in and IDs are never reused', () async {
    await reminders.setEnabled(book.id, true);
    final oldId = notifications.pending.keys.single;
    await repository.returnBook(book);
    final returned = Book.fromMap((await db.query('books')).single);
    await repository.lendBook(returned, 'Jan', DateTime(2030, 9, 1));
    expect(notifications.pending, isEmpty);
    expect(await reminders.enabled(book.id), isFalse);
    await reminders.setEnabled(book.id, true);
    expect(notifications.pending.keys.single, oldId);
    await repository.deleteBook(book.id);
    final other = await repository.addBook(title: 'Other', author: 'Author');
    await repository.lendBook(other, 'Anna', DateTime(2030, 9, 1));
    await reminders.setEnabled(other.id, true);
    expect(notifications.pending.keys.single, greaterThan(oldId));
  });

  test('only nearest 60 dates are scheduled and queue refills', () async {
    await db.transaction((txn) async {
      for (var i = 0; i < 65; i++) {
        final other = Book.fromMap({
          ...book.toMap(),
          'id': 'loan-$i',
          'return_date':
              DateTime(2030, 2, 1).add(Duration(days: i)).toIso8601String(),
        });
        await txn.insert('books', other.toMap());
        await txn
            .insert('return_reminders', {'book_id': other.id, 'enabled': 1});
      }
    });
    await reminders.reconcile();
    expect(notifications.pending, hasLength(60));
    expect(
        notifications.pending.values
            .every((d) => d.isBefore(DateTime(2030, 4, 2))),
        isTrue);
    final later = ReturnReminders(database, notifications,
        now: () => DateTime.utc(2030, 3, 1, 12));
    await later.reconcile();
    expect(notifications.pending.length, lessThan(60));
    expect(notifications.pending.values.any((d) => d.month == 4), isTrue);
  });

  Future<int> addOptedLoan(String id, DateTime due) async {
    await db.insert('books', {
      ...book.toMap(),
      'id': id,
      'return_date': due.toIso8601String(),
    });
    return db.insert('return_reminders', {'book_id': id, 'enabled': 1});
  }

  test(
      'unchanged schedules survive repeated reconciliation and restart untouched',
      () async {
    await reminders.setEnabled(book.id, true);
    final original = Map.of(notifications.pending);
    notifications.schedules.clear();
    notifications.cancellations.clear();
    await reminders.reconcile();
    await reminders.reconcile();
    await ReturnReminders(database, notifications, now: () => now).reconcile();
    expect(notifications.pending, original);
    expect(notifications.schedules, isEmpty);
    expect(notifications.cancellations, isEmpty);
    expect(notifications.permissionRequests, 1);
  });

  test(
      'midway schedule failure preserves other books and recovers after restart',
      () async {
    final ids = [
      for (var i = 0; i < 3; i++)
        await addOptedLoan('multi-$i', DateTime(2030, 2, i + 1)),
    ];
    await reminders.reconcile();
    final oldMiddle = notifications.pending[ids[1]];
    for (var i = 0; i < 3; i++) {
      await db.update(
          'books', {'return_date': DateTime(2030, 3, i + 1).toIso8601String()},
          where: 'id = ?', whereArgs: ['multi-$i']);
    }
    notifications.schedules.clear();
    notifications.cancellations.clear();
    notifications.failScheduleIds.add(ids[1]);
    await expectLater(reminders.reconcile(), throwsStateError);
    expect(notifications.schedules, ids);
    expect(notifications.cancellations, isEmpty);
    expect(notifications.pending[ids[0]]!.month, 3);
    expect(notifications.pending[ids[1]], oldMiddle);
    expect(notifications.pending[ids[2]]!.month, 3);
    expect(await reminders.enabled('multi-1'), isTrue);

    notifications.failScheduleIds.clear();
    notifications.schedules.clear();
    await ReturnReminders(database, notifications, now: () => now).reconcile();
    expect(notifications.schedules, [ids[1]]);
    expect(
        notifications.pending.values.every((date) => date.month == 3), isTrue);
    expect(notifications.permissionRequests, 0);
  });

  test(
      'failed cancellation does not block other cancellations or valid new schedules',
      () async {
    final returned = await addOptedLoan('returned', DateTime(2030, 2, 1));
    final deleted = await addOptedLoan('deleted', DateTime(2030, 2, 2));
    final given = await addOptedLoan('given', DateTime(2030, 2, 3));
    final valid = await addOptedLoan('valid', DateTime(2030, 2, 4));
    await reminders.reconcile();
    await db.update('books', {'status': 'available'},
        where: 'id = ?', whereArgs: ['returned']);
    await db.delete('books', where: 'id = ?', whereArgs: ['deleted']);
    await db.update('books', {'status': 'given'},
        where: 'id = ?', whereArgs: ['given']);
    final fresh = await addOptedLoan('fresh', DateTime(2030, 2, 5));
    notifications.failCancelIds.add(returned);
    notifications.cancellations.clear();
    notifications.schedules.clear();
    await expectLater(reminders.reconcile(), throwsStateError);
    expect(
        notifications.cancellations, containsAll([returned, deleted, given]));
    expect(notifications.schedules, [fresh]);
    expect(notifications.pending.keys.toSet(), {returned, valid, fresh});
    expect(await reminders.enabled('returned'), isFalse);
    expect(await reminders.enabled('valid'), isTrue);
    notifications.failCancelIds.clear();
    notifications.schedules.clear();
    await ReturnReminders(database, notifications, now: () => now).reconcile();
    expect(notifications.pending.keys.toSet(), {valid, fresh});
    expect(notifications.schedules, isEmpty);
  });

  test(
      'date replacement touches only its own ID and permission restoration restores intent',
      () async {
    await reminders.setEnabled(book.id, true);
    final id = notifications.pending.keys.single;
    final other = await addOptedLoan('other', DateTime(2030, 4, 1));
    await reminders.reconcile();
    notifications.schedules.clear();
    notifications.cancellations.clear();
    await repository.updateReturnDate(book.id, DateTime(2030, 3, 1));
    expect(notifications.schedules, [id]);
    expect(notifications.cancellations, isEmpty);
    expect(notifications.pending[other]!.month, 4);
    notifications.allowed = false;
    await reminders.reconcile();
    expect(notifications.pending, isEmpty);
    expect(await reminders.enabled(book.id), isTrue);
    expect(await reminders.enabled('other'), isTrue);
    notifications.allowed = true;
    await reminders.reconcile();
    expect(notifications.pending.keys.toSet(), {id, other});
    expect(notifications.permissionRequests, 1);
  });

  test('timezone change replaces schedules once with the same IDs', () async {
    await reminders.setEnabled(book.id, true);
    final id = notifications.pending.keys.single;
    final oldTime = notifications.pending[id]!.millisecondsSinceEpoch;
    notifications.schedules.clear();
    try {
      tz.setLocalLocation(tz.getLocation('America/New_York'));
      await reminders.reconcile();
      expect(notifications.schedules, [id]);
      expect(notifications.pending[id]!.hour, 9);
      expect(notifications.pending[id]!.millisecondsSinceEpoch, isNot(oldTime));
      notifications.schedules.clear();
      await reminders.reconcile();
      expect(notifications.schedules, isEmpty);
    } finally {
      tz.setLocalLocation(tz.getLocation('Europe/Warsaw'));
    }
  });

  test(
      'failed eviction reserves capacity and nearest-60 refills after recovery',
      () async {
    final ids = [
      for (var i = 0; i < 60; i++)
        await addOptedLoan(
            'queue-$i', DateTime(2030, 3, 1).add(Duration(days: i))),
    ];
    await reminders.reconcile();
    final earlier = await addOptedLoan('earlier', DateTime(2030, 2, 1));
    notifications.failCancelIds.add(ids.last);
    notifications.schedules.clear();
    await expectLater(reminders.reconcile(), throwsStateError);
    expect(notifications.pending, hasLength(60));
    expect(notifications.pending.containsKey(earlier), isFalse);
    expect(notifications.schedules, isEmpty);
    notifications.failCancelIds.clear();
    await ReturnReminders(database, notifications, now: () => now).reconcile();
    expect(notifications.pending, hasLength(60));
    expect(notifications.pending.containsKey(ids.last), isFalse);
    expect(notifications.schedules, [earlier]);
  });

  test('OS failure retains intent for retry without undoing loan writes',
      () async {
    notifications.fail = true;
    expect(await reminders.setEnabled(book.id, true), ReminderResult.failed);
    expect(await reminders.enabled(book.id), isTrue);
    await repository.updateReturnDate(book.id, DateTime(2030, 8, 1));
    expect((await db.query('books')).single['return_date'],
        startsWith('2030-08-01'));
    notifications.fail = false;
    await reminders.reconcile();
    expect(notifications.pending.values.single.month, 8);
  });
}
