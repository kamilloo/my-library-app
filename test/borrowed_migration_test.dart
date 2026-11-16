import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/data/library_database.dart';
import 'package:my_library/data/library_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'fixtures/legacy_library_schema.dart';
import 'readable_loan_test.dart' show invitation, entry, text;

void main() {
  setUpAll(sqfliteFfiInit);
  for (final fail in [false, true]) {
    test(
        'v6 additive migration preserves QR, messages and contacts; rollback=$fail',
        () async {
      final dir = await Directory.systemTemp.createTemp('borrowed-v6');
      final path = '${dir.path}/library.db';
      var db = await databaseFactoryFfi.openDatabase(path,
          options: OpenDatabaseOptions(
              version: 6,
              onCreate: (db, _) async {
                await createLegacySchema(db, 5);
                await db.execute(
                    'ALTER TABLE books RENAME COLUMN directory TO genre');
                await db.execute(
                    'CREATE TABLE genres (id TEXT PRIMARY KEY, name TEXT NOT NULL, normalized_name TEXT NOT NULL UNIQUE)');
              }));
      final qr = invitation();
      await db.insert('borrowed_loans', {
        'loan_id': qr.loanId,
        'transfer_id': qr.transferId,
        'payload': qr.encode(),
        'revision': qr.revision
      });
      await db.insert('loan_contacts',
          {'role': 'borrower', 'loan_id': qr.loanId, 'phone': '123'});
      await db.insert('loan_messages', {
        'role': 'borrower',
        'request_id': 'old',
        'loan_id': qr.loanId,
        'request': 'legacy-payload',
        'decision': null,
        'state': 'prepared'
      });
      final before = <String, List<Map<String, Object?>>>{};
      for (final table in [
        'books',
        'history',
        'genres',
        'return_reminders',
        'borrowed_loans',
        'loan_messages',
        'loan_contacts'
      ]) {
        before[table] = await db.query(table);
      }
      if (fail) {
        await db.execute('CREATE TABLE borrowed_due_overrides (sentinel TEXT)');
      }
      await db.close();
      final database = LibraryDatabase.file(databaseFactoryFfi, path);
      if (fail) {
        await expectLater(database.database, throwsA(isA<DatabaseException>()));
        db = await databaseFactoryFfi.openDatabase(path);
        expect(await db.getVersion(), 6);
        expect(
            await db.rawQuery(
                "SELECT name FROM sqlite_master WHERE name = 'local_borrowed_entries'"),
            isEmpty);
        for (final table in before.keys) {
          expect(await db.query(table), before[table]);
        }
        await db.execute('DROP TABLE borrowed_due_overrides');
        await db.close();
      }
      db = await database.database;
      expect(await db.getVersion(), 8);
      for (final table in before.keys) {
        expect(await db.query(table), before[table]);
      }
      var repo = LibraryRepository(database: database);
      await repo.saveLocalBorrowed(entry(), origin: 'sms', smsSource: text);
      await repo.saveLocalBorrowed(entry(), origin: 'manual');
      await repo.changeBorrowedDueDate(qr, DateTime(2027));
      await db.close();
      final reopened = LibraryDatabase.file(databaseFactoryFfi, path);
      db = await reopened.database;
      repo = LibraryRepository(database: reopened);
      expect((await repo.borrowedLoans()).map((e) => e.origin),
          ['qr', 'manual', 'sms']);
      expect((await repo.borrowedLoans()).first.returnDate, DateTime(2027));
      expect((await db.query('borrowed_loans')).single['payload'], qr.encode());
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      expect(await db.query('loan_messages'), before['loan_messages']);
      await db.close();
      await dir.delete(recursive: true);
    });
  }
}
