import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/data/library_database.dart';
import 'package:my_library/data/library_repository.dart';
import 'package:my_library/models/book.dart';
import 'package:my_library/services/cover_storage.dart';
import 'package:my_library/services/library_backup.dart';
import 'package:my_library/services/return_reminders.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;

class Notifications extends ReminderNotifications {
  final pending = <int, String?>{};
  bool fail = false;

  @override
  Future<void> prepare() async {}
  @override
  Future<bool> authorized({bool request = false}) async {
    expect(request, isFalse);
    return true;
  }

  @override
  Future<Map<int, String?>> pendingRequests() async {
    if (fail) throw StateError('Platform unavailable');
    return pending;
  }

  @override
  Future<void> cancel(int id) async => pending.remove(id);

  @override
  Future<void> schedule(int id, Book book, tz.TZDateTime date) async {
    pending[id] = reminderFingerprint(book, date);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('my_library/backup');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory root;
  late Directory sourceSupport;
  late Directory targetSupport;
  late LibraryDatabase source;
  late LibraryDatabase target;
  late LibraryBackup exporter;
  late LibraryBackup importer;
  late LibraryRepository sourceRepo;
  late LibraryRepository targetRepo;
  late Notifications notifications;

  setUpAll(() {
    sqfliteFfiInit();
    tzdata.initializeTimeZones();
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('manual-library-backup');
    sourceSupport = Directory('${root.path}/source');
    targetSupport = Directory('${root.path}/target');
    source = LibraryDatabase.file(databaseFactoryFfi, '${root.path}/source.db');
    target = LibraryDatabase.file(databaseFactoryFfi, '${root.path}/target.db');
    sourceRepo = LibraryRepository(
        database: source,
        coverStorage: CoverStorage(directory: () async => sourceSupport));
    targetRepo = LibraryRepository(
        database: target,
        coverStorage: CoverStorage(directory: () async => targetSupport));
    notifications = Notifications();
    exporter =
        LibraryBackup(database: source, support: () async => sourceSupport);
    importer = LibraryBackup(
        database: target,
        support: () async => targetSupport,
        reminders:
            ReturnReminders(target, notifications, now: () => DateTime(2026)));
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await (await source.database).close();
    await (await target.database).close();
    await root.delete(recursive: true);
  });

  // The Android bridge has its own archive and SAF implementation.
  // Exercise the exact SQLite files on both sides of that boundary here.
  Future<Directory> prepare() async {
    final exported = await exporter.workspace();
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'export');
      expect(call.arguments['name'], endsWith('.mlbak'));
      expect(call.arguments['schema'], LibraryDatabase.schemaVersion);
      return true;
    });
    expect(await exporter.export(exported), isTrue);
    final importing = await importer.workspace();
    await for (final entity
        in Directory('${exported.path}/export').list(recursive: true)) {
      if (entity is! File) continue;
      final relative = entity.path.substring('${exported.path}/export/'.length);
      final copy = File('${importing.path}/import/$relative');
      await copy.parent.create(recursive: true);
      await entity.copy(copy.path);
    }
    await importer.validateRestore(importing);
    return importing;
  }

  Future<Book> populate() async {
    final input = File('${root.path}/image.jpg');
    await input.writeAsBytes([1, 3, 5, 7]);
    final genre = await sourceRepo.saveGenre('Łódź');
    final book = await sourceRepo.addBook(
      title: 'Żółć',
      author: 'Żaneta',
      genre: genre.name,
      coverUrl: input.path,
    );
    final db = await source.database;
    await db.update(
        'books',
        {
          'status': BookStatus.borrowed.name,
          'borrowed_by': 'Łukasz',
          'borrowed_date': '2026-01-01T00:00:00.000',
          'return_date': '2026-12-05T00:00:00.000',
        },
        where: 'id = ?',
        whereArgs: [book.id]);
    await db.insert(
        'owner_loan_instances', {'book_id': book.id, 'loan_id': 'loan'});
    await db.insert(
        'return_reminders', {'id': 4, 'book_id': book.id, 'enabled': 1});
    await db.update('sqlite_sequence', {'seq': 42},
        where: 'name = ?', whereArgs: ['return_reminders']);
    await sourceRepo.savePreferredOwnerName('Łucja');
    for (final origin in ['sms', 'manual']) {
      await db.insert('local_borrowed_entries', {
        'id': origin,
        'origin': origin,
        'title': 'Śnieg',
        'author': 'Żaneta',
        'owner': 'Łucja',
        'borrowed': '2026-01-01T00:00:00.000',
      });
    }
    return book;
  }

  test('empty export is valid and replaces an existing library', () async {
    await targetRepo.addBook(title: 'Current', author: 'Author');
    await importer.restore(await prepare());
    expect(await targetRepo.books(), isEmpty);
    await sourceRepo.addBook(title: 'Still writable', author: 'Author');
    expect(await sourceRepo.books(), hasLength(1));
  });

  test('populated restore preserves relationships, history and offline cover',
      () async {
    final live = await source.database;
    expect(
        (await live.rawQuery('PRAGMA journal_mode = WAL')).single.values.single,
        'wal');
    await live.rawQuery('PRAGMA wal_autocheckpoint = 0');
    final book = await populate();
    expect(await File('${root.path}/source.db-wal').length(), greaterThan(0));
    notifications.pending[99] =
        jsonEncode([1, 'obsolete', 'Old title', 0, 'UTC']);
    final work = await prepare();
    for (var count = 0; count < 2; count++) {
      await importer.restore(work);
      final restored = (await targetRepo.books()).single;
      expect(restored.id, book.id);
      expect(restored.title, 'Żółć');
      expect(restored.genre, 'Łódź');
      expect(restored.borrowedBy, 'Łukasz');
      expect(await targetRepo.preferredOwnerName(), 'Łucja');
      expect(restored.coverUrl, isNot(book.coverUrl));
      final file = await targetRepo.coverStorage.resolve(restored.coverUrl!);
      expect(await file.readAsBytes(), [1, 3, 5, 7]);
      final db = await target.database;
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      expect(await db.rawQuery('PRAGMA integrity_check'), [
        {'integrity_check': 'ok'}
      ]);
      for (final table in [
        'history',
        'owner_loan_instances',
        'local_preferences',
        'local_borrowed_entries',
        'return_reminders',
        'sqlite_sequence',
      ]) {
        expect(
            await db.query(table), await (await source.database).query(table));
      }
      expect(notifications.pending.keys, [4]);
    }
    final file = await targetRepo.coverStorage.resolve(
      (await targetRepo.books()).single.coverUrl!,
    );
    expect(await file.parent.list().length, 1);
  });

  test('export cancellation and document errors leave active data usable',
      () async {
    final book = await populate();
    messenger.setMockMethodCallHandler(channel, (_) async => false);
    expect(await exporter.export(await exporter.workspace()), isFalse);
    messenger.setMockMethodCallHandler(channel,
        (_) async => throw PlatformException(code: 'document_failure'));
    await expectLater(exporter.export(await exporter.workspace()),
        throwsA(isA<PlatformException>()));
    expect((await sourceRepo.books()).single.id, book.id);
  });

  test('missing staged cover and a reminder failure both roll back', () async {
    final original =
        await targetRepo.addBook(title: 'Original', author: 'Author');
    final incoming = await populate();
    final work = await prepare();
    final staged = File('${work.path}/import/${incoming.coverUrl}');
    await staged.delete();
    await expectLater(importer.restore(work), throwsA(anything));
    expect((await targetRepo.books()).single.id, original.id);
    await staged.writeAsBytes([1, 3, 5, 7]);
    notifications.fail = true;
    await expectLater(importer.restore(work), throwsA(anything));
    expect((await targetRepo.books()).single.id, original.id);
    expect(await Directory('${targetSupport.path}/covers').list().length, 0);
  });

  test('startup journal cleanup keeps referenced covers and SQLite intact',
      () async {
    final image = File('${root.path}/image.jpg');
    await image.writeAsBytes([1]);
    final live = await targetRepo.addBook(
        title: 'Current', author: 'Author', coverUrl: image.path);
    final stale = File('${targetSupport.path}/covers/stale.jpg');
    await stale.writeAsBytes([2]);
    final work = await importer.workspace();
    final journal = File('${work.parent.path}/covers.json');
    await journal
        .writeAsString(jsonEncode([live.coverUrl, 'covers/stale.jpg']));
    await (await target.database).close();
    target = LibraryDatabase.file(databaseFactoryFfi, '${root.path}/target.db');
    final afterRestart =
        LibraryBackup(database: target, support: () async => targetSupport);
    await afterRestart.recoverCovers(startup: true);
    expect(await stale.exists(), isFalse);
    expect(await work.exists(), isFalse);
    expect(await journal.exists(), isFalse);
    expect(
        await (await targetRepo.coverStorage.resolve(live.coverUrl!)).exists(),
        isTrue);
  });
}
