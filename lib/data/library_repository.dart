import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/book.dart';
import '../models/isbn.dart';
import '../models/return_date.dart';
import 'library_database.dart';
import '../services/cover_storage.dart';
import '../services/return_reminders.dart';

class DuplicateIsbnException implements Exception {
  const DuplicateIsbnException();

  static const message = 'Książka z tym numerem ISBN już istnieje.';

  @override
  String toString() => message;
}

class LibraryRepository {
  LibraryRepository(
      {LibraryDatabase? database,
      CoverStorage? coverStorage,
      this.reminders,
      DateTime Function()? clock})
      : _now = clock ?? DateTime.now,
        _database = database ?? LibraryDatabase.instance,
        coverStorage = coverStorage ?? CoverStorage();

  final CoverStorage coverStorage;
  final ReturnReminders? reminders;
  final DateTime Function() _now;

  DateTime get currentTime => _now();

  final LibraryDatabase _database;
  final _uuid = const Uuid();

  Future<List<Book>> books() async {
    final db = await _database.database;
    final rows = await db.query('books', orderBy: 'created_at DESC');
    return rows.map(Book.fromMap).toList();
  }

  Future<List<HistoryEntry>> history() async {
    final db = await _database.database;
    final rows = await db.query('history', orderBy: 'timestamp DESC');
    return rows.map(HistoryEntry.fromMap).toList();
  }

  static const bookHistoryLimit = 50;

  Future<List<HistoryEntry>> historyForBook(String bookId) async {
    final db = await _database.database;
    final rows = await db.query(
      'history',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'timestamp DESC, id DESC',
      limit: bookHistoryLimit,
    );
    return rows.map(HistoryEntry.fromMap).toList();
  }

  Future<void> _assertUniqueBarcode(DatabaseExecutor db, String? barcode,
      {String? exceptId}) async {
    if (barcode == null) return;
    final identity = bookBarcodeIdentity(barcode);
    final rows = await db.query('books',
        columns: ['barcode'],
        where: exceptId == null
            ? 'barcode IS NOT NULL'
            : 'id != ? AND barcode IS NOT NULL',
        whereArgs: exceptId == null ? null : [exceptId]);
    if (rows.any(
        (row) => bookBarcodeIdentity(row['barcode'] as String?) == identity)) {
      throw const DuplicateIsbnException();
    }
  }

  Future<Book> addBook({
    required String title,
    required String author,
    String description = '',
    String? coverUrl,
    String? barcode,
    String condition = 'Dobry',
    String directory = 'Bez kategorii',
  }) async {
    final normalizedBarcode = normalizeBookBarcode(barcode);
    final db = await _database.database;
    await _assertUniqueBarcode(db, normalizedBarcode);
    final storedCover = await coverStorage.persist(coverUrl);
    final now = _now();
    final book = Book(
      id: _uuid.v4(),
      title: title.trim(),
      author: author.trim(),
      description: description.trim(),
      coverUrl: storedCover,
      barcode: normalizedBarcode,
      condition: condition,
      directory: directory,
      createdAt: now,
      updatedAt: now,
    );
    try {
      await db.transaction((txn) async {
        // Recheck under SQLite's write lock, including equivalent 10/13 values
        // that the unchanged text-only unique index cannot compare.
        await _assertUniqueBarcode(txn, normalizedBarcode);
        try {
          await txn.insert('books', book.toMap());
        } on DatabaseException catch (error) {
          // The preflight check cannot prevent concurrent inserts. Translate only
          // the barcode unique constraint, leaving all other DB failures intact.
          if (normalizedBarcode != null &&
              error.isUniqueConstraintError('books.barcode')) {
            throw const DuplicateIsbnException();
          }
          rethrow;
        }
        await txn.insert(
            'history', _event(book, 'added', 'Dodano na półkę').toMap());
      });
    } catch (_) {
      if (storedCover != coverUrl) await _deleteUnusedCover(storedCover);
      rethrow;
    }
    return book;
  }

  /// Updates metadata only; loan state and linked history remain untouched.
  /// Additional metadata fields can be added here without changing loan writes.
  Future<Book> updateBook({
    required String id,
    required String title,
    required String author,
    String? barcode,
    required String condition,
    String? coverUrl,
    bool updateCover = false,
  }) async {
    if (title.trim().isEmpty || author.trim().isEmpty) {
      throw ArgumentError('Title and author are required');
    }
    final normalizedBarcode = normalizeBookBarcode(barcode);
    final db = await _database.database;
    final storedCover =
        updateCover ? await coverStorage.persist(coverUrl) : null;
    String? previousCover;
    late final Book result;
    try {
      result = await db.transaction((txn) async {
        final rows = await txn.query('books', where: 'id = ?', whereArgs: [id]);
        if (rows.isEmpty) throw StateError('Book no longer exists');
        final current = rows.single;
        previousCover = current['cover_url'] as String?;
        await _assertUniqueBarcode(txn, normalizedBarcode, exceptId: id);
        final changes = <String, Object?>{
          'title': title.trim(),
          'author': author.trim(),
          'barcode': normalizedBarcode,
          'condition': condition,
          if (updateCover) 'cover_url': storedCover,
        };
        if (changes.entries
            .every((entry) => current[entry.key] == entry.value)) {
          return Book.fromMap(current);
        }
        changes['updated_at'] = _now().toIso8601String();
        try {
          await txn.update('books', changes, where: 'id = ?', whereArgs: [id]);
        } on DatabaseException catch (error) {
          if (normalizedBarcode != null &&
              error.isUniqueConstraintError('books.barcode')) {
            throw const DuplicateIsbnException();
          }
          rethrow;
        }
        return Book.fromMap({...current, ...changes});
      });
    } catch (_) {
      // Only rollback-created files are candidates here; never existing covers.
      if (storedCover != coverUrl) await _deleteUnusedCover(storedCover);
      rethrow;
    }
    // The write has committed. Cleanup cannot change the saved result.
    if (updateCover && previousCover != storedCover) {
      await _deleteUnusedCover(previousCover);
    }
    return result;
  }

  Future<void> _refreshReminders() async {
    try {
      await reminders?.reconcile();
    } catch (error) {
      // Loan writes are committed; retry OS synchronization on next app resume.
      debugPrint('Reminder synchronization failed: $error');
    }
  }

  Future<Book> updateReturnDate(String bookId, DateTime? date) =>
      _updateReturnDate(bookId, date);

  Future<Book> extendLoan(String bookId, DateTime date) =>
      _updateReturnDate(bookId, date, extension: true);

  Future<Book> _updateReturnDate(String bookId, DateTime? date,
      {bool extension = false}) async {
    final db = await _database.database;
    var changed = false;
    final updated = await db.transaction((txn) async {
      final rows =
          await txn.query('books', where: 'id = ?', whereArgs: [bookId]);
      if (rows.isEmpty) {
        throw const ReturnDateException('Nie znaleziono książki.');
      }
      final current = Book.fromMap(rows.single);
      if (current.status != BookStatus.borrowed) {
        throw const ReturnDateException(
            'Termin zwrotu można zmienić tylko dla wypożyczonej książki.');
      }
      final oldDate =
          current.returnDate == null ? null : calendarDate(current.returnDate!);
      final newDate = date == null ? null : calendarDate(date);
      final now = _now();
      if (extension) {
        final validation = loanExtensionValidation(oldDate, newDate, now);
        if (validation != null) throw ReturnDateException(validation);
      } else if (oldDate == newDate) {
        return current;
      }
      if (newDate != null && newDate.isBefore(calendarDate(now))) {
        throw const ReturnDateException(
            'Termin zwrotu nie może być w przeszłości.');
      }
      final changes = <String, Object?>{
        'return_date': newDate?.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };
      await txn.update('books', changes, where: 'id = ?', whereArgs: [bookId]);
      await txn.insert(
          'history',
          HistoryEntry(
            id: _uuid.v4(),
            bookId: current.id,
            bookTitle: current.title,
            action: extension ? 'loan_extended' : 'return_date_changed',
            detail:
                '${extension ? 'Przedłużono wypożyczenie' : 'Zmieniono termin zwrotu'}: ${returnDateHistoryValue(oldDate)} → ${returnDateHistoryValue(newDate)}',
            timestamp: now,
          ).toMap());
      changed = true;
      return Book.fromMap({...rows.single, ...changes});
    });
    if (changed) await _refreshReminders();
    return updated;
  }

  Future<void> lendBook(Book book, String borrower, DateTime? dueDate) =>
      _transitionLoan(book, 'borrowed', person: borrower, dueDate: dueDate);

  Future<void> giveBook(Book book, String recipient) =>
      _transitionLoan(book, 'given', person: recipient);

  Future<void> returnBook(Book book) => _transitionLoan(book, 'returned');

  Future<void> deleteBook(String bookId) async {
    final db = await _database.database;
    final previousCover = await db.transaction((txn) async {
      final rows = await txn.query('books',
          columns: ['cover_url'], where: 'id = ?', whereArgs: [bookId]);
      await txn.update('return_reminders', {'enabled': 0},
          where: 'book_id = ?', whereArgs: [bookId]);
      await txn.delete('books', where: 'id = ?', whereArgs: [bookId]);
      return rows.isEmpty ? null : rows.single['cover_url'] as String?;
    });
    await _refreshReminders();
    await _deleteUnusedCover(previousCover);
  }

  Future<void> _deleteUnusedCover(String? reference) async {
    if (reference == null || !CoverStorage.isManaged(reference)) return;
    try {
      final db = await _database.database;
      // Check and delete while holding SQLite's write lock, so another save
      // cannot start referencing this file between the check and deletion.
      await db.transaction((txn) async {
        final users = await txn.query('books',
            columns: ['id'],
            where: 'cover_url = ?',
            whereArgs: [reference],
            limit: 1);
        if (users.isEmpty) await coverStorage.delete(reference);
      });
    } catch (error, stackTrace) {
      // Cleanup is best effort, including unexpected storage/DB failures.
      // Preserve the original transaction error or successful committed result.
      debugPrint('Cover cleanup failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _transitionLoan(Book snapshot, String action,
      {String? person, DateTime? dueDate}) async {
    final name = person?.trim();
    if (action != 'returned' && (name == null || name.isEmpty)) {
      throw ArgumentError('Wpisz imię osoby.');
    }
    final db = await _database.database;
    await db.transaction((txn) async {
      final rows = await txn.query('books',
          where: 'id = ?', whereArgs: [snapshot.id], limit: 1);
      if (rows.isEmpty) throw StateError('Nie znaleziono książki.');
      final current = Book.fromMap(rows.single);
      final valid = switch (action) {
        'borrowed' => current.status == BookStatus.available,
        'returned' => current.status == BookStatus.borrowed,
        'given' => current.status != BookStatus.given,
        _ => false,
      };
      if (!valid) throw StateError('Stan książki nie pozwala na tę operację.');
      if (snapshot.status != current.status) {
        throw StateError('Stan książki zmienił się. Odśwież dane książki.');
      }
      if (current.status == BookStatus.borrowed &&
          action != 'borrowed' &&
          (current.status != BookStatus.borrowed ||
              snapshot.borrowedDate != current.borrowedDate ||
              snapshot.borrowedBy != current.borrowedBy)) {
        throw StateError('Wypożyczenie zmieniło się. Odśwież dane książki.');
      }
      final now = _now();
      final changes = <String, Object?>{
        'status': switch (action) {
          'borrowed' => 'borrowed',
          'given' => 'given',
          _ => 'available',
        },
        'borrowed_by': action == 'returned' ? null : name,
        'borrowed_date': action == 'returned'
            ? null
            : action == 'given' && current.status == BookStatus.borrowed
                ? current.borrowedDate?.toIso8601String()
                : now.toIso8601String(),
        'return_date': action == 'borrowed' ? dueDate?.toIso8601String() : null,
        'updated_at': now.toIso8601String(),
      };
      // Never write metadata from a potentially stale UI snapshot.
      await txn
          .update('books', changes, where: 'id = ?', whereArgs: [current.id]);
      final detail = switch (action) {
        'borrowed' => 'Wypożyczono: $name',
        'given' => 'Oddano na stałe: $name',
        _ => 'Oznaczono jako zwróconą',
      };
      await txn.insert('history', _event(current, action, detail, now).toMap());
      await txn.update('return_reminders', {'enabled': 0},
          where: 'book_id = ?', whereArgs: [current.id]);
    });
    await _refreshReminders();
  }

  HistoryEntry _event(Book book, String action,
          [String? detail, DateTime? at]) =>
      HistoryEntry(
        id: _uuid.v4(),
        bookId: book.id,
        bookTitle: book.title,
        action: action,
        detail: detail,
        timestamp: at ?? _now(),
      );
}
