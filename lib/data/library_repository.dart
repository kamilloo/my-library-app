import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/book.dart';
import '../models/isbn.dart';
import 'library_database.dart';

class DuplicateIsbnException implements Exception {
  const DuplicateIsbnException();

  static const message = 'Książka z tym numerem ISBN już istnieje.';

  @override
  String toString() => message;
}

class LibraryRepository {
  LibraryRepository({LibraryDatabase? database})
      : _database = database ?? LibraryDatabase.instance;

  final LibraryDatabase _database;
  final _uuid = const Uuid();

  Future<List<Book>> books() async {
    final db = await _database.database;
    final rows = await db.query('books', orderBy: 'created_at DESC');
    if (rows.isEmpty && !kReleaseMode) await _seed();
    final current = rows.isEmpty
        ? await db.query('books', orderBy: 'created_at DESC')
        : rows;
    return current.map(Book.fromMap).toList();
  }

  Future<List<HistoryEntry>> history() async {
    final db = await _database.database;
    final rows = await db.query('history', orderBy: 'timestamp DESC');
    return rows.map(HistoryEntry.fromMap).toList();
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
    if (normalizedBarcode != null) {
      // Older versions saved formatted ISBNs, so normalize existing values too.
      final rows = await db.query('books',
          columns: ['barcode'], where: 'barcode IS NOT NULL');
      if (rows.any((row) =>
          normalizeBookBarcode(row['barcode'] as String?) ==
          normalizedBarcode)) {
        throw const DuplicateIsbnException();
      }
    }
    final now = DateTime.now();
    final book = Book(
      id: _uuid.v4(),
      title: title.trim(),
      author: author.trim(),
      description: description.trim(),
      coverUrl: coverUrl,
      barcode: normalizedBarcode,
      condition: condition,
      directory: directory,
      createdAt: now,
      updatedAt: now,
    );
    await db.transaction((txn) async {
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
    return book;
  }

  Future<void> lendBook(Book book, String borrower, DateTime? dueDate) async {
    final updated = book.copyWith(
      status: BookStatus.borrowed,
      borrowedBy: borrower.trim(),
      borrowedDate: DateTime.now(),
      returnDate: dueDate,
    );
    await _updateWithHistory(
        updated, 'borrowed', 'Wypożyczono: ${borrower.trim()}');
  }

  Future<void> giveBook(Book book, String recipient) async {
    final updated = book.copyWith(
      status: BookStatus.given,
      borrowedBy: recipient.trim(),
      borrowedDate: DateTime.now(),
    );
    await _updateWithHistory(
        updated, 'given', 'Oddano na stałe: ${recipient.trim()}');
  }

  Future<void> returnBook(Book book) async {
    final updated =
        book.copyWith(status: BookStatus.available, clearLoan: true);
    await _updateWithHistory(updated, 'returned', 'Oznaczono jako zwróconą');
  }

  Future<void> deleteBook(String bookId) async {
    final db = await _database.database;
    await db.delete('books', where: 'id = ?', whereArgs: [bookId]);
  }

  Future<void> _updateWithHistory(
      Book book, String action, String detail) async {
    final db = await _database.database;
    await db.transaction((txn) async {
      await txn
          .update('books', book.toMap(), where: 'id = ?', whereArgs: [book.id]);
      await txn.insert('history', _event(book, action, detail).toMap());
    });
  }

  HistoryEntry _event(Book book, String action, [String? detail]) =>
      HistoryEntry(
        id: _uuid.v4(),
        bookId: book.id,
        bookTitle: book.title,
        action: action,
        detail: detail,
        timestamp: DateTime.now(),
      );

  Future<void> _seed() async {
    await addBook(
      title: 'Siedem sióstr',
      author: 'Lucinda Riley',
      barcode: '9788379859436',
      directory: 'Fikcja',
      coverUrl: 'https://covers.openlibrary.org/b/isbn/9788379859436-L.jpg',
    );

    await addBook(
      title: 'Sześć cztery',
      author: 'Hideo Yokoyama',
      barcode: '9788308065174',
      directory: 'Kryminał',
      coverUrl: 'https://covers.openlibrary.org/b/isbn/9788308065174-L.jpg',
    );

    await addBook(
      title: 'Sprawa honoru',
      author: 'Lynne Olson',
      barcode: '9788392140160',
      directory: 'Historia',
      coverUrl: 'https://covers.openlibrary.org/b/isbn/9788392140160-L.jpg',
    );
  }
}
