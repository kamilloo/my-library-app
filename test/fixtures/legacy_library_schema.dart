// Frozen schema snapshots, intentionally independent of production onCreate.
// Version 1 shipped books/history + partial barcode index; version 2 added
// the book/timestamp history index; version 3 added reminder intent.
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> createLegacySchema(Database db, int version) async {
  await db.execute('''
    CREATE TABLE books (
      id TEXT PRIMARY KEY, title TEXT NOT NULL, author TEXT NOT NULL,
      description TEXT NOT NULL DEFAULT '', cover_url TEXT, barcode TEXT,
      condition TEXT NOT NULL, directory TEXT NOT NULL, status TEXT NOT NULL,
      borrowed_by TEXT, borrowed_date TEXT, return_date TEXT,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL
    )
  ''');
  await db.execute(
      'CREATE UNIQUE INDEX idx_books_barcode ON books(barcode) WHERE barcode IS NOT NULL');
  await db.execute('''
    CREATE TABLE history (
      id TEXT PRIMARY KEY, book_id TEXT NOT NULL, book_title TEXT NOT NULL,
      action TEXT NOT NULL, detail TEXT, timestamp TEXT NOT NULL,
      FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE
    )
  ''');
  if (version >= 2) {
    await db.execute(
        'CREATE INDEX idx_history_book_timestamp ON history(book_id, timestamp DESC, id DESC)');
  }
  if (version >= 3) {
    await db.execute('''
      CREATE TABLE return_reminders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id TEXT NOT NULL UNIQUE,
        enabled INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }
}
