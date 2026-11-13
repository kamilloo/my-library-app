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
  if (version >= 4) {
    await db.execute(
        'CREATE TABLE owner_loan_instances (book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE, loan_id TEXT NOT NULL UNIQUE)');
    await db.execute(
        'CREATE TABLE loan_transfers (loan_id TEXT PRIMARY KEY, payload TEXT NOT NULL)');
    await db.execute(
        "CREATE TABLE borrowed_loans (loan_id TEXT PRIMARY KEY, transfer_id TEXT NOT NULL UNIQUE, payload TEXT NOT NULL, revision INTEGER NOT NULL, local_status TEXT NOT NULL DEFAULT 'active')");
  }
  if (version >= 5) {
    await db.execute(
        'CREATE TABLE loan_messages (role TEXT NOT NULL, request_id TEXT NOT NULL, loan_id TEXT NOT NULL, request TEXT NOT NULL, decision TEXT, state TEXT NOT NULL, PRIMARY KEY (role, request_id))');
    await db.execute(
        'CREATE TABLE loan_contacts (role TEXT NOT NULL, loan_id TEXT NOT NULL, phone TEXT NOT NULL, PRIMARY KEY (role, loan_id))');
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
