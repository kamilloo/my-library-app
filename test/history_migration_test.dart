import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/data/library_database.dart';
import 'package:my_library/data/library_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  for (final legacyVersion in [1, 2]) {
    test(
        'version $legacyVersion upgrade preserves data and adds reminder storage',
        () async {
      final directory =
          await Directory.systemTemp.createTemp('history-migration-');
      final path = '${directory.path}/library.db';
      Database? upgraded;
      try {
        final source =
            await LibraryDatabase.inMemory(databaseFactoryFfi).database;
        final schemas = await source.rawQuery(
            "SELECT sql FROM sqlite_master WHERE type = 'table' AND name IN ('books', 'history')");
        await source.close();
        final legacy = await databaseFactoryFfi.openDatabase(path,
            options: OpenDatabaseOptions(
                version: legacyVersion,
                onCreate: (db, _) async {
                  for (final schema in schemas) {
                    await db.execute(schema['sql'] as String);
                  }
                  if (legacyVersion == 2) {
                    await db.execute(
                        'CREATE INDEX idx_history_book_timestamp ON history(book_id, timestamp DESC, id DESC)');
                  }
                }));
        await legacy.insert('books', {
          'id': 'existing',
          'title': 'Title',
          'author': 'Author',
          'condition': 'Dobry',
          'directory': 'Bez kategorii',
          'status': 'available',
          'created_at': '2020-01-01T00:00:00.000',
          'updated_at': '2020-01-01T00:00:00.000',
        });
        await legacy.insert('history', {
          'id': 'event',
          'book_id': 'existing',
          'book_title': 'Title',
          'action': 'added',
          'timestamp': '2020-01-01T00:00:00.000',
        });
        final booksBefore = await legacy.query('books');
        final historyBefore = await legacy.query('history');
        await legacy.close();

        final database = LibraryDatabase.file(databaseFactoryFfi, path);
        upgraded = await database.database;
        expect(await upgraded.getVersion(), 3);
        expect(await upgraded.query('books'), booksBefore);
        expect(await upgraded.query('history'), historyBefore);
        expect(await upgraded.query('return_reminders'), isEmpty);
        expect(
            (await LibraryRepository(database: database)
                    .historyForBook('existing'))
                .single
                .id,
            'event');
        expect(
            await upgraded.rawQuery(
                "SELECT name FROM sqlite_master WHERE name = 'idx_history_book_timestamp'"),
            hasLength(1));
      } finally {
        await upgraded?.close();
        await directory.delete(recursive: true);
      }
    });
  }
}
