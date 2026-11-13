import 'package:path/path.dart';
import '../models/genre.dart';
import 'package:sqflite/sqflite.dart';

class LibraryDatabase {
  LibraryDatabase._()
      : _factory = null,
        _path = null;

  // Uses the production schema with an isolated in-memory SQLite database.
  LibraryDatabase.inMemory(DatabaseFactory factory)
      : _factory = factory,
        _path = null;

  LibraryDatabase.file(DatabaseFactory factory, String path)
      : _factory = factory,
        _path = path;

  final String? _path;

  final DatabaseFactory? _factory;

  static final instance = LibraryDatabase._();
  Database? _database;

  Future<Database> get database async => _database ??= await _open();

  static Future<void> _createHistoryIndex(Database db) => db.execute(
      'CREATE INDEX IF NOT EXISTS idx_history_book_timestamp ON history(book_id, timestamp DESC, id DESC)');

  static Future<void> _createReminders(Database db) => db.execute('''
    CREATE TABLE return_reminders (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      book_id TEXT NOT NULL UNIQUE,
      enabled INTEGER NOT NULL DEFAULT 0
    )
  ''');

  static Future<void> _createTransfers(Database db) async {
    await db.execute('''CREATE TABLE owner_loan_instances (
      book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
      loan_id TEXT NOT NULL UNIQUE
    )''');
    await db.execute(
        'CREATE TABLE loan_transfers (loan_id TEXT PRIMARY KEY, payload TEXT NOT NULL)');
    await db.execute("""CREATE TABLE borrowed_loans (
      loan_id TEXT PRIMARY KEY, transfer_id TEXT NOT NULL UNIQUE,
      payload TEXT NOT NULL, revision INTEGER NOT NULL,
      local_status TEXT NOT NULL DEFAULT 'active'
    )""");
  }

  static Future<void> _createMessages(Database db) async {
    await db.execute('''CREATE TABLE loan_messages (
      role TEXT NOT NULL, request_id TEXT NOT NULL, loan_id TEXT NOT NULL,
      request TEXT NOT NULL, decision TEXT, state TEXT NOT NULL,
      PRIMARY KEY (role, request_id)
    )''');
    await db.execute('''CREATE TABLE loan_contacts (
      role TEXT NOT NULL, loan_id TEXT NOT NULL, phone TEXT NOT NULL,
      PRIMARY KEY (role, loan_id)
    )''');
  }

  static Future<void> _createGenres(Database db) async {
    await db.execute(
        'CREATE TABLE genres (id TEXT PRIMARY KEY, name TEXT NOT NULL, normalized_name TEXT NOT NULL UNIQUE)');
    for (final name in starterGenres) {
      await db.insert('genres', {
        'id': 'starter-${normalizedGenre(name)}',
        'name': name,
        'normalized_name': normalizedGenre(name)
      });
    }
  }

  static Future<void> _upgradeGenres(Database db) async {
    // Rebuild without renaming the old parent: child references keep books(id).
    final schema = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'books'");
    final original = schema.single['sql']! as String;
    final replacement = original
        .replaceFirst(
            RegExp(r'CREATE TABLE\s+["\x60\[]?books["\x60\]]?',
                caseSensitive: false),
            'CREATE TABLE books_v6')
        .replaceFirst(
            RegExp(r'directory\s+TEXT\s+NOT\s+NULL', caseSensitive: false),
            "genre TEXT NOT NULL DEFAULT 'Bez gatunku'");
    if (replacement == original || !replacement.contains('genre TEXT')) {
      throw StateError('Nieobsługiwany schemat książek.');
    }
    final indexes = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE tbl_name = 'books' AND type IN ('index', 'trigger') AND sql IS NOT NULL");
    await db.execute(replacement);
    final columns = (await db.rawQuery('PRAGMA table_info(books)'))
        .map((r) => r['name']! as String)
        .where((n) => n != 'directory')
        .toList();
    final names = columns.map((n) => '"${n.replaceAll('"', '""')}"').join(', ');
    await db.execute(
        "INSERT INTO books_v6 ($names, genre) SELECT $names, 'Bez gatunku' FROM books");
    await db.execute('DROP TABLE books');
    await db.execute('ALTER TABLE books_v6 RENAME TO books');
    for (final index in indexes) {
      await db.execute(index['sql']! as String);
    }
    await _createGenres(db);
    if ((await db.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
      throw StateError('Naruszone relacje bazy danych.');
    }
  }

  Future<Database> _open() async {
    final factory = _factory ?? databaseFactory;
    final path = _path ??
        (_factory != null
            ? inMemoryDatabasePath
            : join(await getDatabasesPath(), 'my_library.db'));
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 6,
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) await _createHistoryIndex(db);
          if (oldVersion < 3) await _createReminders(db);
          if (oldVersion < 4) await _createTransfers(db);
          if (oldVersion < 5) await _createMessages(db);
          if (oldVersion < 6) await _upgradeGenres(db);
        },
        onConfigure: (db) async {
          final version =
              Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version')) ??
                  0;
          // Must happen BEFORE sqflite starts its upgrade transaction.
          await db.execute(
              'PRAGMA foreign_keys = ${version > 0 && version < 6 ? 'OFF' : 'ON'}');
        },
        onOpen: (db) => db.execute('PRAGMA foreign_keys = ON'),
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
              genre TEXT NOT NULL DEFAULT 'Bez gatunku',
              status TEXT NOT NULL,
              borrowed_by TEXT,
              borrowed_date TEXT,
              return_date TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
          await db.execute(
              'CREATE UNIQUE INDEX idx_books_barcode ON books(barcode) WHERE barcode IS NOT NULL');
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
          await _createHistoryIndex(db);
          await _createReminders(db);
          await _createTransfers(db);
          await _createMessages(db);
          await _createGenres(db);
        },
      ),
    );
  }
}
