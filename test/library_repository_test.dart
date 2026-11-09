import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/data/library_database.dart';
import 'package:my_library/data/library_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late LibraryRepository repository;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    final database = LibraryDatabase.inMemory(databaseFactoryFfi);
    db = await database.database;
    repository = LibraryRepository(database: database);
  });
  tearDown(() async => db.close());

  Future<void> add(String? isbn) async {
    await repository.addBook(title: 'Książka', author: 'Autor', barcode: isbn);
  }

  test('rejects repeated normalized ISBNs without adding history', () async {
    await add('978-0-525-55947-4');
    await expectLater(
        add(' 9780525559474 '), throwsA(isA<DuplicateIsbnException>()));
    expect((await db.query('books')).single['barcode'], '9780525559474');
    expect(await db.query('history'), hasLength(1));
  });

  for (final values in [
    ['978-0-525-55947-4', '9780525559474'],
    ['0-8044-2957-x', '080442957X'],
  ]) {
    test('preserves existing data when rejecting legacy ISBN ${values.first}',
        () async {
      await add(values.last);
      await db.update('books', {'barcode': values.first});
      final booksBefore = await db.query('books');
      final historyBefore = await db.query('history');
      final schemaBefore = await db.rawQuery(
          'SELECT type, name, sql FROM sqlite_master ORDER BY type, name');
      final versionBefore = await db.getVersion();

      await expectLater(
          add(values.last), throwsA(isA<DuplicateIsbnException>()));

      expect(await db.query('books'), booksBefore);
      expect(await db.query('history'), historyBefore);
      expect(
          await db.rawQuery(
              'SELECT type, name, sql FROM sqlite_master ORDER BY type, name'),
          schemaBefore);
      expect(await db.getVersion(), versionBefore);
      expect(versionBefore, 1);
    });
  }

  test('normalizes lowercase ISBN-10 check digits without adding history',
      () async {
    await add('0-8044-2957-x');
    final booksBefore = await db.query('books');
    final historyBefore = await db.query('history');
    await expectLater(
        add('080442957X'), throwsA(isA<DuplicateIsbnException>()));
    expect(booksBefore.single['barcode'], '080442957X');
    expect(await db.query('books'), booksBefore);
    expect(await db.query('history'), historyBefore);
  });

  test('saves distinct ISBNs', () async {
    await add('9780525559474');
    await add('080442957X');
    expect(await db.query('books'), hasLength(2));
    expect(await db.query('history'), hasLength(2));
  });

  test('saves multiple books with null, empty or whitespace ISBNs', () async {
    for (final isbn in [null, '', '   ', '']) {
      await add(isbn);
    }
    final rows = await db.query('books');
    expect(rows, hasLength(4));
    expect(rows.every((row) => row['barcode'] == null), isTrue);
    expect(await db.query('history'), hasLength(4));
  });

  test('preserves other barcodes and rejects exact duplicates', () async {
    await add(' barcode-123 ');
    await expectLater(
        add('barcode-123'), throwsA(isA<DuplicateIsbnException>()));
    expect((await db.query('books')).single['barcode'], 'barcode-123');
  });

  test('translates the SQLite constraint if a duplicate appears after checking',
      () async {
    // Simulate a competing insert after preflight using a real SQLite trigger.
    await db.execute("""
      CREATE TRIGGER competing_insert BEFORE INSERT ON books
      WHEN NEW.id != 'competing'
      BEGIN
        INSERT INTO books
          (id, title, author, barcode, condition, directory, status,
           created_at, updated_at)
        VALUES ('competing', NEW.title, NEW.author, NEW.barcode, NEW.condition,
                NEW.directory, NEW.status, NEW.created_at, NEW.updated_at);
      END
    """);
    await expectLater(
        add('9780525559474'), throwsA(isA<DuplicateIsbnException>()));
    expect(await db.query('books'), isEmpty);
    expect(await db.query('history'), isEmpty);
  });

  test('does not translate an unrelated unique constraint on books', () async {
    await db.execute('CREATE UNIQUE INDEX test_title ON books(title)');
    await add('9780525559474');
    await expectLater(add('080442957X'), throwsA(isA<DatabaseException>()));
    expect(await db.query('books'), hasLength(1));
    expect(await db.query('history'), hasLength(1));
  });

  test('propagates history failures and rolls back the book insert', () async {
    await db.execute('DROP TABLE history');
    await expectLater(add('9780525559474'), throwsA(isA<DatabaseException>()));
    expect(await db.query('books'), isEmpty);
  });
}
