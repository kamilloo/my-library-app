import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/data/library_database.dart';
import 'package:my_library/data/library_repository.dart';
import 'package:my_library/models/book.dart';
import 'package:my_library/models/genre.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late Database db;
  late LibraryRepository repository;
  setUp(() async {
    final database = LibraryDatabase.inMemory(databaseFactoryFfi);
    db = await database.database;
    repository = LibraryRepository(database: database);
  });
  tearDown(() async => db.close());

  test('fresh install has exact starters, no books and default genre schema',
      () async {
    expect(await repository.books(), isEmpty);
    expect((await db.query('genres')).map((r) => r['name']),
        unorderedEquals(starterGenres));
    final columns = await db.rawQuery('PRAGMA table_info(books)');
    expect(columns.any((r) => r['name'] == 'directory'), false);
    final genre = columns.singleWhere((r) => r['name'] == 'genre');
    expect(genre['notnull'], 1);
    expect(genre['dflt_value'], "'Bez gatunku'");
    expect((await repository.genres()).first.bookCount, 0);
  });

  test('create trims, normalizes Unicode and counts assigned books', () async {
    final g = await repository.saveGenre('  Żółć  ');
    expect(g.name, 'Żółć');
    final book =
        await repository.addBook(title: 'T', author: 'A', genre: g.name);
    expect(book.genre, g.name);
    expect(
        (await repository.genres()).singleWhere((x) => x.id == g.id).bookCount,
        1);
    await expectLater(
        repository.saveGenre(' żółć '), throwsA(isA<GenreException>()));
    await expectLater(repository.saveGenre('Z\u0307o\u0301łc\u0301'),
        throwsA(isA<GenreException>()));
    await expectLater(
        db.insert('genres', {
          'id': 'duplicate',
          'name': 'other',
          'normalized_name': normalizedGenre(g.name)
        }),
        throwsA(isA<DatabaseException>()));
  });

  for (final input in [
    '',
    '  ',
    'A\nB',
    'A\rB',
    'A\tB',
    'A\u007fB',
    'Bez gatunku',
    ' BEZ KATEGORII ',
    'a' * 61
  ]) {
    test('reject invalid or reserved name: ${input.codeUnits}', () async {
      await expectLater(
          repository.saveGenre(input), throwsA(isA<GenreException>()));
      expect(await db.query('genres'), hasLength(11));
    });
  }

  test('60 Unicode scalars accepted and system entry is immutable', () async {
    await repository.saveGenre('😀' * 60);
    await expectLater(
        repository.deleteGenre(''), throwsA(isA<GenreException>()));
    await expectLater(
        repository.saveGenre('Other', id: ''), throwsA(isA<GenreException>()));
  });

  test('add/update reject missing genres without writing books or history',
      () async {
    await expectLater(
        repository.addBook(title: 'T', author: 'A', genre: 'Missing'),
        throwsA(isA<GenreException>()));
    expect(await db.query('books'), isEmpty);
    final book = await repository.addBook(title: 'T', author: 'A');
    final before = await db.query('books');
    await expectLater(
        repository.updateBook(
            id: book.id,
            title: 'T',
            author: 'A',
            condition: 'Dobry',
            genre: 'Missing'),
        throwsA(isA<GenreException>()));
    expect(await db.query('books'), before);
    expect(await db.query('history'), hasLength(1));
  });

  for (final status in BookStatus.values) {
    test(
        'genre edit rename and delete preserve ${status.name} book and linked data',
        () async {
      final g = await repository.saveGenre('Custom');
      final now = DateTime(2025);
      final book = Book(
          id: 'book',
          title: 'T',
          author: 'A',
          description: 'Opis',
          coverUrl: 'covers/test.jpg',
          barcode: '080442957X',
          genre: g.name,
          status: status,
          borrowedBy: 'Anna',
          borrowedDate: now,
          returnDate: DateTime(2027),
          createdAt: now,
          updatedAt: now);
      await db.insert('books', book.toMap());
      await db.insert('history', {
        'id': 'h',
        'book_id': book.id,
        'book_title': 'T',
        'action': 'borrowed',
        'timestamp': '2025'
      });
      await db.insert('return_reminders', {'book_id': book.id, 'enabled': 1});
      await db.insert(
          'owner_loan_instances', {'book_id': book.id, 'loan_id': 'loan'});
      await db.insert('loan_transfers',
          {'loan_id': 'loan', 'payload': 'original QR revision'});
      await db.insert('loan_messages', {
        'role': 'owner',
        'request_id': 'request',
        'loan_id': 'loan',
        'request': 'original SMS',
        'decision': 'decision',
        'state': 'approved'
      });
      final tables = [
        'history',
        'return_reminders',
        'owner_loan_instances',
        'loan_transfers',
        'loan_messages'
      ];
      final before = {for (final t in tables) t: await db.query(t)};
      final edited = await repository.updateBook(
          id: book.id,
          title: book.title,
          author: book.author,
          barcode: book.barcode,
          condition: book.condition,
          genre: 'Fantastyka');
      for (final entry in book.toMap().entries) {
        if (!['genre', 'updated_at'].contains(entry.key)) {
          expect(edited.toMap()[entry.key], entry.value, reason: entry.key);
        }
      }
      final starter = (await repository.genres())
          .singleWhere((g) => g.name == 'Fantastyka');
      await repository.saveGenre('Nowa nazwa', id: starter.id);
      expect((await repository.books()).single.genre, 'Nowa nazwa');
      await repository.deleteGenre(starter.id);
      expect((await repository.books()).single.genre, defaultGenre);
      for (final t in tables) {
        expect(await db.query(t), before[t], reason: t);
      }
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await repository.deleteGenre(g.id);
      expect((await repository.genres()).any((x) => x.id == g.id), false);
    });
  }

  for (final operation in ['rename', 'delete']) {
    test('failed $operation rolls back book reassignment and genre registry',
        () async {
      final g = await repository.saveGenre('Custom');
      await repository.addBook(title: 'T', author: 'A', genre: g.name);
      final books = await db.query('books');
      final genres = await db.query('genres');
      if (operation == 'rename') {
        await db.execute(
            "CREATE TRIGGER fail BEFORE UPDATE OF genre ON books BEGIN SELECT RAISE(ABORT, 'failure'); END");
        await expectLater(repository.saveGenre('Renamed', id: g.id),
            throwsA(isA<GenreException>()));
      } else {
        await db.execute(
            "CREATE TRIGGER fail BEFORE DELETE ON genres BEGIN SELECT RAISE(ABORT, 'failure'); END");
        await expectLater(
            repository.deleteGenre(g.id), throwsA(isA<DatabaseException>()));
      }
      expect(await db.query('books'), books);
      expect(await db.query('genres'), genres);
    });
  }

  test('rename rejects duplicates without modifying assignments', () async {
    final g = await repository.saveGenre('Custom');
    await repository.addBook(title: 'T', author: 'A', genre: g.name);
    await expectLater(repository.saveGenre(' FANTASTYKA ', id: g.id),
        throwsA(isA<GenreException>()));
    expect((await repository.books()).single.genre, 'Custom');
  });

  test('reopen persists names and never resurrects deleted starters', () async {
    final temp = await Directory.systemTemp.createTemp('genres-');
    final path = '${temp.path}/library.db';
    var database = LibraryDatabase.file(databaseFactoryFfi, path);
    var repo = LibraryRepository(database: database);
    var sqlite = await database.database;
    final starter =
        (await repo.genres()).singleWhere((g) => g.name == 'Fantastyka');
    await repo.deleteGenre(starter.id);
    final custom = await repo.saveGenre('Własny');
    await repo.addBook(title: 'T', author: 'A', genre: custom.name);
    await sqlite.close();
    database = LibraryDatabase.file(databaseFactoryFfi, path);
    repo = LibraryRepository(database: database);
    sqlite = await database.database;
    expect((await repo.genres()).any((g) => g.name == 'Fantastyka'), false);
    expect((await repo.books()).single.genre, custom.name);
    await sqlite.close();
    await temp.delete(recursive: true);
  });
}
