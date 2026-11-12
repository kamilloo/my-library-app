import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/data/library_database.dart';
import 'package:my_library/data/library_repository.dart';
import 'package:my_library/services/cover_storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fixtures/legacy_library_schema.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  for (final legacyVersion in [1, 2, 3]) {
    test(
        'version $legacyVersion preserves complete collection and repeated v3 reopen is idempotent',
        () async {
      final root =
          await Directory.systemTemp.createTemp('sqlite-upgrade-audit-');
      final path = '${root.path}/my_library.db';
      Database? db;
      try {
        final support = await Directory('${root.path}/support/covers')
            .create(recursive: true);
        final image = File('${support.path}/legacy.jpg');
        await image.writeAsBytes([1, 7, 9, 3]);
        db = await databaseFactoryFfi.openDatabase(path,
            options: OpenDatabaseOptions(
              version: legacyVersion,
              onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
              onCreate: (db, _) => createLegacySchema(db, legacyVersion),
            ));
        for (var index = 0; index < 3; index++) {
          await db.insert('books', {
            'id': 'book-$index',
            'title': 'Żółć: tytuł $index',
            'author': 'Łukasz Ćma $index',
            'description': 'Istniejący opis\nDrugi wiersz $index',
            'cover_url': [
              null,
              'covers/legacy.jpg',
              'https://example.com/cover.jpg'
            ][index],
            'barcode': [null, '0-8044-2957-x', '978-0-525-55947-4'][index],
            'condition': ['Nowa', 'Dobry', 'Zużyta'][index],
            'directory': 'Istniejąca półka $index',
            'status': ['available', 'borrowed', 'given'][index],
            'borrowed_by': index == 0 ? null : 'Osoba $index',
            'borrowed_date': index == 0 ? null : '2026-01-02T12:34:56.000',
            'return_date': index == 1 ? '2026-11-30T00:00:00.000' : null,
            'created_at': '2025-01-02T03:04:05.000',
            'updated_at': '2026-10-10T09:08:07.000',
          });
        }
        final actions = [
          'added',
          'borrowed',
          'returned',
          'given',
          if (legacyVersion == 3) ...['return_date_changed', 'loan_extended']
        ];
        for (var i = 0; i < actions.length; i++) {
          await db.insert('history', {
            'id': 'event-$i',
            'book_id': 'book-${i % 3}',
            'book_title': 'Tytuł w chwili zdarzenia $i',
            'action': actions[i],
            'detail': i == 0 ? null : 'Szczegóły: Żółć → Ćma $i',
            'timestamp': DateTime(2026, 1, i + 1, 12, 30).toIso8601String(),
          });
        }
        if (legacyVersion == 3) {
          await db.insert(
              'return_reminders', {'id': 7, 'book_id': 'book-1', 'enabled': 1});
          await db.insert('return_reminders',
              {'id': 42, 'book_id': 'book-2', 'enabled': 0});
          // Cancellation tombstones deliberately have no FK.
          await db.insert('return_reminders',
              {'id': 99, 'book_id': 'deleted-book', 'enabled': 0});
        }
        final books = await db.query('books', orderBy: 'id');
        final history = await db.query('history', orderBy: 'id');
        final reminders = legacyVersion == 3
            ? await db.query('return_reminders', orderBy: 'id')
            : <Map<String, Object?>>[];
        await db.close();
        List<Map<String, Object?>>? firstSchema;
        for (var pass = 0; pass < 2; pass++) {
          final database = LibraryDatabase.file(databaseFactoryFfi, path);
          db = await database.database;
          expect(await db.getVersion(), 4);
          expect(await db.query('books', orderBy: 'id'), books);
          expect(await db.query('history', orderBy: 'id'), history);
          expect(await db.query('return_reminders', orderBy: 'id'), reminders);
          expect(
              (await db.rawQuery('PRAGMA foreign_keys')).single.values.single,
              1);
          expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
          expect(
              (await db.rawQuery('PRAGMA integrity_check'))
                  .single
                  .values
                  .single,
              'ok');
          final schema = await db.rawQuery(
              "SELECT type, name, tbl_name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name");
          firstSchema ??= schema;
          expect(schema, firstSchema);
          for (final name in [
            'idx_books_barcode',
            'idx_history_book_timestamp'
          ]) {
            expect(
                schema.where((entry) => entry['name'] == name), hasLength(1));
          }
          expect(
              schema.where((entry) => entry['type'] == 'table'), hasLength(6));
          final loaded = await LibraryRepository(database: database).books();
          expect(loaded, hasLength(3));
          final storage = CoverStorage(
              directory: () async => Directory('${root.path}/support'));
          expect(
              await (await storage.resolve('covers/legacy.jpg')).readAsBytes(),
              [1, 7, 9, 3]);
          await db.close();
        }
        // AUTOINCREMENT must preserve its high-water mark across current-version opens.
        db = await LibraryDatabase.file(databaseFactoryFfi, path).database;
        final id = await db.insert(
            'return_reminders', {'book_id': 'new-intent', 'enabled': 0});
        expect(id, legacyVersion == 3 ? greaterThan(99) : greaterThan(0));
      } finally {
        if (db?.isOpen == true) await db!.close();
        await root.delete(recursive: true);
      }
    });
  }

  test(
      'fresh schema enforces nullable unique barcode, FK cascade and reminder book uniqueness',
      () async {
    final database = LibraryDatabase.inMemory(databaseFactoryFfi);
    final db = await database.database;
    try {
      final repository = LibraryRepository(
          database: database, clock: () => DateTime(2026, 11, 10));
      final first = await repository.addBook(title: 'One', author: 'A');
      await repository.addBook(title: 'Two', author: 'A');
      await db.insert('return_reminders', {'book_id': first.id, 'enabled': 1});
      await expectLater(
          db.insert('return_reminders', {'book_id': first.id, 'enabled': 0}),
          throwsA(isA<DatabaseException>()));
      await expectLater(
          db.insert('history', {
            'id': 'orphan',
            'book_id': 'missing',
            'book_title': 'T',
            'action': 'added',
            'timestamp': '2026-11-10T00:00:00.000',
          }),
          throwsA(isA<DatabaseException>()));
      await repository.deleteBook(first.id);
      expect(
          await db
              .query('history', where: 'book_id = ?', whereArgs: [first.id]),
          isEmpty);
      expect(
          (await db.query('return_reminders',
                  where: 'book_id = ?', whereArgs: [first.id]))
              .single['enabled'],
          0);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    } finally {
      await db.close();
    }
  });

  test(
      'actual v3 defaults nullable columns and partial unique index match audit',
      () async {
    final db = await LibraryDatabase.inMemory(databaseFactoryFfi).database;
    try {
      await db.insert('books', {
        'id': 'defaults',
        'title': 'T',
        'author': 'A',
        'condition': 'Dobry',
        'directory': 'Bez kategorii',
        'status': 'available',
        'created_at': '2026-11-10T00:00:00.000',
        'updated_at': '2026-11-10T00:00:00.000',
      });
      final row = (await db.query('books')).single;
      expect(row['description'], '');
      for (final name in [
        'barcode',
        'cover_url',
        'borrowed_by',
        'borrowed_date',
        'return_date'
      ]) {
        expect(row[name], isNull, reason: name);
      }
      await db.insert('return_reminders', {'book_id': 'defaults'});
      expect((await db.query('return_reminders')).single['enabled'], 0);
      final columns = await db.rawQuery('PRAGMA table_info(books)');
      expect(columns, hasLength(14));
      expect(columns.singleWhere((c) => c['name'] == 'id')['pk'], 1);
      expect(columns.singleWhere((c) => c['name'] == 'title')['notnull'], 1);
      final index = (await db.rawQuery('PRAGMA index_list(books)'))
          .singleWhere((i) => i['name'] == 'idx_books_barcode');
      expect(index['unique'], 1);
      expect(index['partial'], 1);
    } finally {
      await db.close();
    }
  });
}
