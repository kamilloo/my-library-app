import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class LibraryDatabase {
  LibraryDatabase._();

  static final instance = LibraryDatabase._();
  Database? _database;

  Future<Database> get database async => _database ??= await _open();

  Future<Database> _open() async {
    final root = await getDatabasesPath();
    return openDatabase(
      join(root, 'my_library.db'),
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE books (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            author TEXT NOT NULL,
            description TEXT NOT NULL DEFAULT '',
            cover_url TEXT,
            barcode TEXT,
            condition TEXT NOT NULL,
            directory TEXT NOT NULL,
            status TEXT NOT NULL,
            borrowed_by TEXT,
            borrowed_date TEXT,
            return_date TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute('CREATE UNIQUE INDEX idx_books_barcode ON books(barcode) WHERE barcode IS NOT NULL');
        await db.execute('''
          CREATE TABLE history (
            id TEXT PRIMARY KEY,
            book_id TEXT NOT NULL,
            book_title TEXT NOT NULL,
            action TEXT NOT NULL,
            detail TEXT,
            timestamp TEXT NOT NULL,
            FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE
          )
        ''');
      },
    );
  }
}
