import 'dart:io';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/data/library_database.dart';
import 'package:my_library/models/genre.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'fixtures/legacy_library_schema.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  for (final version in [1, 2, 3, 4, 5]) {
    test(
        'populated v$version upgrades to v6 without losing any nonclassification data',
        () async {
      final temp = await Directory.systemTemp.createTemp('genre-migrate-');
      final path = '${temp.path}/library.db';
      var db = await databaseFactoryFfi.openDatabase(path,
          options: OpenDatabaseOptions(
            version: version,
            onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
            onCreate: (db, _) => createLegacySchema(db, version),
          ));
      try {
        for (var i = 0; i < 3; i++) {
          await db.insert('books', {
            'id': 'book-$i',
            'title': 'Żółć $i',
            'author': 'Łukasz $i',
            'description': 'Opis\n$i',
            'cover_url': i == 0 ? null : 'covers/$i.jpg',
            'barcode': i == 0 ? '080442957X' : null,
            'condition': 'Dobry',
            'directory': ['Bez kategorii', 'Fantastyka', 'Stara półka'][i],
            'status': ['available', 'borrowed', 'given'][i],
            'borrowed_by': i == 0 ? null : 'Anna',
            'borrowed_date': '2025-01-01T01:02:03.000',
            'return_date': i == 1 ? '2027-02-01T00:00:00.000' : null,
            'created_at': '2024-01-01T01:02:03.004',
            'updated_at': '2025-02-01T04:05:06.007',
          });
          await db.insert('history', {
            'id': 'h$i',
            'book_id': 'book-$i',
            'book_title': 'T$i',
            'action': 'added',
            'detail': 'opis',
            'timestamp': '2024'
          });
        }
        final tables = ['history'];
        if (version >= 3) {
          tables.add('return_reminders');
          await db.insert('return_reminders',
              {'id': 99, 'book_id': 'book-1', 'enabled': 1});
        }
        if (version >= 4) {
          tables.addAll(
              ['owner_loan_instances', 'loan_transfers', 'borrowed_loans']);
          await db.insert(
              'owner_loan_instances', {'book_id': 'book-1', 'loan_id': 'loan'});
          await db.insert('loan_transfers', {
            'loan_id': 'loan',
            'payload': '{"revision":4,"snapshot":"QR Żółć"}'
          });
          await db.insert('borrowed_loans', {
            'loan_id': 'borrowed',
            'transfer_id': 'transfer',
            'payload': '{"snapshot":"borrowed"}',
            'revision': 3,
            'local_status': 'active'
          });
        }
        if (version >= 5) {
          tables.addAll(['loan_messages', 'loan_contacts']);
          await db.insert('loan_messages', {
            'role': 'owner',
            'request_id': 'request',
            'loan_id': 'loan',
            'request': '{"sms":"request"}',
            'decision': '{"sms":"decision"}',
            'state': 'approved'
          });
          await db.insert('loan_contacts',
              {'role': 'owner', 'loan_id': 'loan', 'phone': '+48123456789'});
        }
        final before = {for (final t in tables) t: await db.query(t)};
        final books = await db.query('books', orderBy: 'id');
        await db.close();
        for (var pass = 0; pass < 2; pass++) {
          db = await LibraryDatabase.file(databaseFactoryFfi, path).database;
          expect(await db.getVersion(), 6);
          expect(
              await db.query('books', orderBy: 'id'),
              books
                  .map((r) => {...r}..remove('directory'))
                  .map((r) => {...r, 'genre': defaultGenre})
                  .toList());
          for (final t in tables) {
            expect(await db.query(t), before[t], reason: t);
          }
          expect((await db.query('genres')).map((r) => r['name']),
              unorderedEquals(starterGenres));
          final columns = await db.rawQuery('PRAGMA table_info(books)');
          expect(columns.any((r) => r['name'] == 'directory'), false);
          expect(
              columns.singleWhere((r) => r['name'] == 'genre')['notnull'], 1);
          expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
          expect(
              Sqflite.firstIntValue(await db.rawQuery('PRAGMA foreign_keys')),
              1);
          await expectLater(
              db.insert(
                  'books',
                  {...books.first}
                    ..remove('directory')
                    ..['id'] = 'duplicate'),
              throwsA(isA<DatabaseException>()));
          expect(await db.query('books'), hasLength(3));
          await db.close();
        }
      } finally {
        if (db.isOpen) await db.close();
        await temp.delete(recursive: true);
      }
    });
  }

  for (final failure in ['registry', 'foreign-key']) {
    test('migration failure ($failure) rolls back schema rows and version',
        () async {
      final temp = await Directory.systemTemp.createTemp('genre-rollback-');
      final path = '${temp.path}/library.db';
      var db = await databaseFactoryFfi.openDatabase(path,
          options: OpenDatabaseOptions(
              version: 5, onCreate: (db, _) => createLegacySchema(db, 5)));
      await db.insert('books', {
        'id': 'b',
        'title': 'T',
        'author': 'A',
        'condition': 'Dobry',
        'directory': 'Discarded',
        'status': 'available',
        'created_at': '2025',
        'updated_at': '2025'
      });
      if (failure == 'registry') {
        await db.execute('CREATE TABLE genres (unexpected TEXT)');
      } else {
        await db.insert('history', {
          'id': 'orphan',
          'book_id': 'missing',
          'book_title': 'T',
          'action': 'added',
          'timestamp': '2025'
        });
      }
      final schema = await db
          .rawQuery('SELECT name, sql FROM sqlite_master ORDER BY name');
      final books = await db.query('books');
      await db.close();
      await expectLater(
          LibraryDatabase.file(databaseFactoryFfi, path).database,
          throwsA(failure == 'registry'
              ? isA<DatabaseException>()
              : isA<StateError>()));
      db = await databaseFactoryFfi.openDatabase(path);
      expect(await db.getVersion(), 5);
      expect(await db.query('books'), books);
      expect(
          await db
              .rawQuery('SELECT name, sql FROM sqlite_master ORDER BY name'),
          schema);
      await db.close();
      await temp.delete(recursive: true);
    });
  }
}
