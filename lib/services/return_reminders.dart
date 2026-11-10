import 'package:timezone/timezone.dart' as tz;

import '../data/library_database.dart';
import '../models/book.dart';

abstract class ReminderNotifications {
  Future<void> prepare();
  Future<bool> authorized({bool request = false});
  Future<void> schedule(int id, Book book, tz.TZDateTime date);
  Future<void> cancel(int id);
  Future<bool> needsRationale() async => false;
  Future<void> openSettings() async {}
}

tz.TZDateTime? reminderDate(
    Book book, bool enabled, tz.Location location, DateTime now) {
  final due = book.returnDate;
  if (!enabled ||
      book.status != BookStatus.borrowed ||
      book.borrowedBy?.trim().isNotEmpty != true ||
      due == null) {
    return null;
  }
  final date = tz.TZDateTime(location, due.year, due.month, due.day, 9);
  return date.isAfter(now) ? date : null;
}

enum ReminderResult { enabled, disabled, denied, ineligible, failed }

class ReturnReminders {
  ReturnReminders(this.database, this.notifications, {DateTime Function()? now})
      : now = now ?? DateTime.now;
  final LibraryDatabase database;
  final ReminderNotifications notifications;
  final DateTime Function() now;
  Future<void> _tail = Future.value();

  // Serialize permission, DB and OS operations to prevent stale schedules winning.
  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<bool> enabled(String bookId) async {
    final db = await database.database;
    final rows = await db.query('return_reminders',
        where: 'book_id = ?', whereArgs: [bookId], limit: 1);
    return rows.isNotEmpty && rows.single['enabled'] == 1;
  }

  Future<ReminderResult> setEnabled(String bookId, bool value) =>
      _serial(() async {
        try {
          final db = await database.database;
          if (value) {
            await notifications.prepare();
            final books = await db.query('books',
                where: 'id = ?', whereArgs: [bookId], limit: 1);
            if (books.isEmpty ||
                reminderDate(
                        Book.fromMap(books.single), true, tz.local, now()) ==
                    null) {
              return ReminderResult.ineligible;
            }
            if (!await notifications.authorized(request: true)) {
              return ReminderResult.denied;
            }
          }
          await db.transaction((txn) async {
            final rows = await txn.query('return_reminders',
                where: 'book_id = ?', whereArgs: [bookId], limit: 1);
            if (rows.isEmpty) {
              await txn.insert('return_reminders',
                  {'book_id': bookId, 'enabled': value ? 1 : 0});
            } else {
              await txn.update('return_reminders', {'enabled': value ? 1 : 0},
                  where: 'book_id = ?', whereArgs: [bookId]);
            }
          });
          await _reconcile();
          return value ? ReminderResult.enabled : ReminderResult.disabled;
        } catch (_) {
          return ReminderResult.failed;
        }
      });

  Future<void> reconcile() => _serial(_reconcile);

  Future<void> _reconcile() async {
    await notifications.prepare();
    final db = await database.database;
    final rows = await db.query('return_reminders');
    final allowed = await notifications.authorized();
    final candidates = <({int id, Book book, tz.TZDateTime date})>[];
    for (final row in rows) {
      final id = row['id'] as int;
      final books = await db.query('books',
          where: 'id = ?', whereArgs: [row['book_id']], limit: 1);
      final book = books.isEmpty ? null : Book.fromMap(books.single);
      final date = book == null
          ? null
          : reminderDate(book, row['enabled'] == 1, tz.local, now());
      // Cancel first, including returned/deleted/expired and revoked permissions.
      // Reusing persisted IDs also replaces existing notifications after restart.
      await notifications.cancel(id);
      if (book == null || book.status != BookStatus.borrowed) {
        await db.update('return_reminders', {'enabled': 0},
            where: 'id = ?', whereArgs: [id]);
      }
      if (allowed && book != null && date != null) {
        candidates.add((id: id, book: book, date: date));
      }
    }
    candidates.sort((a, b) => a.date.compareTo(b.date));
    // Leave room below iOS's 64 pending request limit. Refill on app resume.
    for (final candidate in candidates.take(60)) {
      await notifications.schedule(
          candidate.id, candidate.book, candidate.date);
    }
  }
}
