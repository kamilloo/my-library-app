import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/data/library_database.dart';
import 'package:my_library/data/library_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late LibraryRepository repository;
  var tick = 0;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    final database = LibraryDatabase.inMemory(databaseFactoryFfi);
    db = await database.database;
    tick = 0;
    repository = LibraryRepository(
        database: database,
        clock: () =>
            DateTime(2026, 11, 10).add(Duration(microseconds: tick++)));
  });
  tearDown(() async => db.close());

  Future<void> add(String? isbn) async {
    await repository.addBook(title: 'Książka', author: 'Autor', barcode: isbn);
  }

  test('edit preserves identity, loan data, metadata and history', () async {
    final book = await repository.addBook(
        title: 'Old',
        author: 'Author',
        barcode: '9780525559474',
        description: 'Description',
        genre: 'Fantastyka',
        coverUrl: 'https://example.com/cover.jpg');
    await repository.lendBook(book, 'Borrower', DateTime(2030));
    final before = (await db.query('books')).single;
    final history = await db.query('history');
    final edited = await repository.updateBook(
        id: book.id,
        title: ' Corrected ',
        author: ' New author ',
        barcode: '0-8044-2957-x',
        condition: 'Zużyta');
    final after = (await db.query('books')).single;
    expect(edited.id, book.id);
    expect(edited.title, 'Corrected');
    expect(edited.author, 'New author');
    expect(edited.barcode, '080442957X');
    expect(edited.condition, 'Zużyta');
    for (final key in [
      'id',
      'created_at',
      'status',
      'borrowed_by',
      'borrowed_date',
      'return_date',
      'description',
      'genre',
      'cover_url'
    ]) {
      expect(after[key], before[key], reason: key);
    }
    expect(
        edited.updatedAt
            .isAfter(DateTime.parse(before['updated_at'] as String)),
        isTrue);
    expect(await db.query('books'), hasLength(1));
    expect(await db.query('history'), history);
    final unchanged = await repository.updateBook(
        id: book.id,
        title: edited.title,
        author: edited.author,
        barcode: edited.barcode,
        condition: edited.condition);
    expect(unchanged.updatedAt, edited.updatedAt);
  });

  test(
      'edit excludes itself and rejects normalized legacy duplicate atomically',
      () async {
    final book = await repository.addBook(
        title: 'One', author: 'Author', barcode: '9780525559474');
    await repository.updateBook(
        id: book.id,
        title: 'One',
        author: 'Author',
        barcode: '978-0-525-55947-4',
        condition: 'Dobry');
    await add('080442957X');
    await db.update('books', {'barcode': '0-8044-2957-x'},
        where: 'id != ?', whereArgs: [book.id]);
    final before = await db.query('books');
    final history = await db.query('history');
    await expectLater(
        repository.updateBook(
            id: book.id,
            title: 'Changed',
            author: 'Author',
            barcode: '080442957X',
            condition: 'Nowa'),
        throwsA(isA<DuplicateIsbnException>()));
    expect(await db.query('books'), before);
    expect(await db.query('history'), history);
    await expectLater(
        repository.updateBook(
            id: book.id, title: ' ', author: 'Author', condition: 'Dobry'),
        throwsArgumentError);
  });

  test(
      'edited borrowed book can be returned without losing metadata or history',
      () async {
    final book = await repository.addBook(
      title: 'Original',
      author: 'Author',
      barcode: '9780525559474',
      description: 'Keep description',
      genre: 'Fantastyka',
      coverUrl: 'https://example.com/cover.jpg',
    );
    await repository.lendBook(book, 'Borrower', DateTime(2030, 6, 15));
    final borrowed = (await db.query('books')).single;
    final historyBefore = await db.query('history');
    expect(historyBefore.map((row) => row['action']),
        unorderedEquals(['added', 'borrowed']));

    await repository.updateBook(
      id: book.id,
      title: 'Corrected title',
      author: 'Corrected author',
      barcode: '0-8044-2957-x',
      condition: 'Zużyta',
    );
    // Read back from SQLite, as a subsequent screen/session would do.
    final edited = (await repository.books()).single;
    final editedRow = edited.toMap();
    for (final key in [
      'id',
      'created_at',
      'description',
      'genre',
      'cover_url',
      'status',
      'borrowed_by',
      'borrowed_date',
      'return_date',
    ]) {
      expect(editedRow[key], borrowed[key], reason: key);
    }
    expect(await db.query('history'), historyBefore);

    await repository.returnBook(edited);
    final returned = (await db.query('books')).single;
    expect(returned['status'], 'available');
    for (final key in ['borrowed_by', 'borrowed_date', 'return_date']) {
      expect(returned[key], isNull, reason: key);
    }
    for (final key in [
      'id',
      'created_at',
      'title',
      'author',
      'barcode',
      'condition',
      'description',
      'genre',
      'cover_url',
    ]) {
      expect(returned[key], editedRow[key], reason: key);
    }
    expect(returned['title'], 'Corrected title');
    expect(returned['author'], 'Corrected author');
    expect(returned['barcode'], '080442957X');
    expect(returned['condition'], 'Zużyta');
    expect(await db.query('books'), hasLength(1));
    final historyAfter = await db.query('history');
    expect(historyAfter, hasLength(historyBefore.length + 1));
    for (final event in historyBefore) {
      expect(
          historyAfter.singleWhere((row) => row['id'] == event['id']), event);
    }
    final returnedEvent =
        historyAfter.singleWhere((row) => row['action'] == 'returned');
    expect(returnedEvent['book_id'], book.id);
    expect(returnedEvent['book_title'], 'Corrected title');
    expect(historyAfter.where((row) => row['action'] == 'added'), hasLength(1));
  });

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
      expect(versionBefore, 6);
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
          (id, title, author, barcode, condition, genre, status,
           created_at, updated_at)
        VALUES ('competing', NEW.title, NEW.author, NEW.barcode, NEW.condition,
                NEW.genre, NEW.status, NEW.created_at, NEW.updated_at);
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
