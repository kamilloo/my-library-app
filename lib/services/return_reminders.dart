import 'dart:convert';

import 'package:timezone/timezone.dart' as tz;

import '../data/library_database.dart';
import '../models/book.dart';

abstract class ReminderNotifications {
  Future<void> prepare();
  Future<bool> authorized({bool request = false});
  Future<void> schedule(int id, Book book, tz.TZDateTime date);
  Future<void> cancel(int id);
  Future<Map<int, String?>> pendingRequests();
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

// Stored in the plugin's persisted payload, so comparisons work after restart.
// Older book-ID-only payloads are replaced once without changing notification IDs.
String reminderFingerprint(Book book, tz.TZDateTime date) => jsonEncode([
      1,
      book.id,
      book.title,
      date.millisecondsSinceEpoch,
      date.location.name,
    ]);

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
      if (book == null || book.status != BookStatus.borrowed) {
        await db.update('return_reminders', {'enabled': 0},
            where: 'id = ?', whereArgs: [id]);
      }
      if (allowed && book != null && date != null) {
        candidates.add((id: id, book: book, date: date));
      }
    }
    candidates.sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });
    final desired = {
      for (final candidate in candidates.take(60)) candidate.id: candidate,
    };
    // If inventory cannot be read, make no destructive guesses.
    final pending = Map<int, String?>.of(await notifications.pendingRequests());
    final ownedIds = rows.map((row) => row['id'] as int).toSet();
    final active = pending.keys.where(ownedIds.contains).toSet();
    final failures = <int>[];

    // Free slots only for ineligible or displaced reminders. A failed cancellation
    // remains counted, so a refill cannot push our pending total above 60.
    for (final id in active.toList()) {
      if (desired.containsKey(id)) continue;
      try {
        await notifications.cancel(id);
        active.remove(id);
      } catch (_) {
        failures.add(id);
      }
    }

    for (final candidate in desired.values) {
      final fingerprint = reminderFingerprint(candidate.book, candidate.date);
      if (active.contains(candidate.id) &&
          pending[candidate.id] == fingerprint) {
        continue;
      }
      if (!active.contains(candidate.id) && active.length >= 60) {
        failures.add(candidate.id);
        continue;
      }
      try {
        // Scheduling the same stable ID replaces it; do not first cancel a
        // changed schedule or touch unrelated valid requests.
        await notifications.schedule(
            candidate.id, candidate.book, candidate.date);
        active.add(candidate.id);
      } catch (_) {
        // Conservatively reserve the slot: a platform call might have applied
        // before reporting an error. Re-read native inventory next time.
        active.add(candidate.id);
        failures.add(candidate.id);
      }
    }
    if (failures.isNotEmpty) {
      throw StateError(
          'Could not synchronize reminder IDs: ${failures.join(', ')}');
    }
  }
}
