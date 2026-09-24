import 'package:uuid/uuid.dart';

import '../models/book.dart';
import 'library_database.dart';

class LibraryRepository {
  LibraryRepository({LibraryDatabase? database})
      : _database = database ?? LibraryDatabase.instance;

  final LibraryDatabase _database;
  final _uuid = const Uuid();

  Future<List<Book>> books() async {
    final db = await _database.database;
    final rows = await db.query('books', orderBy: 'created_at DESC');
    if (rows.isEmpty) await _seed();
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
    String? barcode,
    String condition = 'Good',
    String directory = 'Unsorted',
  }) async {
    final now = DateTime.now();
    final book = Book(
      id: _uuid.v4(),
      title: title.trim(),
      author: author.trim(),
      description: description.trim(),
      barcode: barcode?.trim().isEmpty == true ? null : barcode?.trim(),
      condition: condition,
      directory: directory,
      createdAt: now,
      updatedAt: now,
    );
    final db = await _database.database;
    await db.transaction((txn) async {
      await txn.insert('books', book.toMap());
      await txn.insert('history', _event(book, 'added').toMap());
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
    await _updateWithHistory(updated, 'borrowed', 'Lent to ${borrower.trim()}');
  }

  Future<void> giveBook(Book book, String recipient) async {
    final updated = book.copyWith(
      status: BookStatus.given,
      borrowedBy: recipient.trim(),
      borrowedDate: DateTime.now(),
    );
    await _updateWithHistory(updated, 'given', 'Given to ${recipient.trim()}');
  }

  Future<void> returnBook(Book book) async {
    final updated = book.copyWith(status: BookStatus.available, clearLoan: true);
    await _updateWithHistory(updated, 'returned', 'Marked as returned');
  }

  Future<void> _updateWithHistory(Book book, String action, String detail) async {
    final db = await _database.database;
    await db.transaction((txn) async {
      await txn.update('books', book.toMap(), where: 'id = ?', whereArgs: [book.id]);
      await txn.insert('history', _event(book, action, detail).toMap());
    });
  }

  HistoryEntry _event(Book book, String action, [String? detail]) => HistoryEntry(
        id: _uuid.v4(),
        bookId: book.id,
        bookTitle: book.title,
        action: action,
        detail: detail,
        timestamp: DateTime.now(),
      );

  Future<void> _seed() async {
    await addBook(
      title: 'The Midnight Library',
      author: 'Matt Haig',
      description: 'Between life and death there is a library.',
      barcode: '9780525559474',
      directory: 'Fiction',
    );
    await addBook(
      title: 'Atomic Habits',
      author: 'James Clear',
      barcode: '9780735211292',
      directory: 'Non-fiction',
    );
    await addBook(
      title: 'Project Hail Mary',
      author: 'Andy Weir',
      barcode: '9780593135204',
      directory: 'Fiction',
    );
  }
}
