import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/data/library_database.dart';
import 'package:my_library/data/library_repository.dart';
import 'package:my_library/models/book.dart';
import 'package:my_library/models/readable_loan.dart';
import 'package:my_library/services/cover_storage.dart';
import 'package:my_library/services/library_backup.dart';
import 'package:my_library/services/return_reminders.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;

class Notifications extends ReminderNotifications {
  final pending = <int, String?>{};
  bool fail = false;
  Future<void> Function()? beforeInventory;

  @override
  Future<void> prepare() async {}
  @override
  Future<bool> authorized({bool request = false}) async {
    expect(request, isFalse);
    return true;
  }

  @override
  Future<Map<int, String?>> pendingRequests() async {
    await beforeInventory?.call();
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

class PersistentJournalFactory implements DatabaseFactory {
  @override
  Future<Database> openDatabase(String path,
      {OpenDatabaseOptions? options}) async {
    final db = await databaseFactoryFfi.openDatabase(path, options: options);
    if (path.contains('/export/database/') && options?.readOnly != true) {
      // Match the Android default seen on API 34.
      await db.rawQuery('PRAGMA journal_mode = PERSIST');
    }
    return db;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ObservedDatabase extends LibraryDatabase {
  ObservedDatabase(String path) : super.file(databaseFactoryFfi, path);

  final exclusiveRequested = Completer<void>();

  @override
  Future<T> exclusive<T>(Future<T> Function() action) {
    final result = super.exclusive(action);
    exclusiveRequested.complete();
    return result;
  }
}

class PausedCoverStorage extends CoverStorage {
  PausedCoverStorage(Directory support) : super(directory: () async => support);

  final entered = Completer<void>();
  final proceed = Completer<void>();

  @override
  Future<String?> persist(String? reference) async {
    final path = await super.persist(reference);
    entered.complete();
    await proceed.future;
    return path;
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
    source = LibraryDatabase.file(
        PersistentJournalFactory(), '${root.path}/source.db');
    target = LibraryDatabase.file(databaseFactoryFfi, '${root.path}/target.db');
    sourceRepo = LibraryRepository(
        database: source,
        clock: () => DateTime(2026),
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
      final files = await Directory('${exported.path}/export/database')
          .list()
          .map((entry) => entry.uri.pathSegments.last)
          .toList();
      expect(files, ['my_library.db']);
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
    await sourceRepo.savePreferredOwnerName('Łucja');
    await sourceRepo.lendBook(book, 'Łukasz', DateTime(2026, 12, 5));
    final invitation = await sourceRepo.loanInvitation(book.id);
    // This fixture represents both sides of a loan in one library.
    await sourceRepo.importLoan(invitation);
    final request = await sourceRepo.prepareExtension(
        invitation.loanId, DateTime(2026, 12, 12));
    await sourceRepo.markRequestSent(request.requestId);
    final decision = await sourceRepo.decideExtension(request, true);
    await sourceRepo.importConfirmation(decision);
    final imported = (await sourceRepo.borrowedLoans()).single;
    await sourceRepo.changeBorrowedDueDate(imported, DateTime(2026, 12, 19));
    await sourceRepo.saveContact('owner', invitation.loanId, '+48 000 000 001');
    await sourceRepo.saveContact(
        'borrower', invitation.loanId, '+48 000 000 002');
    await db.insert(
        'return_reminders', {'id': 4, 'book_id': book.id, 'enabled': 1});
    await db.update('sqlite_sequence', {'seq': 42},
        where: 'name = ?', whereArgs: ['return_reminders']);
    final local = ReadableLoan(
      title: 'Śnieg',
      author: 'Żaneta',
      owner: 'Łucja',
      borrowedAt: DateTime(2026),
      returnDate: DateTime(2026, 12, 20),
    );
    await sourceRepo.saveLocalBorrowed(local, origin: 'manual');
    await sourceRepo.saveLocalBorrowed(local,
        origin: 'sms', smsSource: readableInvitation(invitation));
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
        'loan_transfers',
        'borrowed_loans',
        'loan_messages',
        'loan_contacts',
        'borrowed_due_overrides',
        'local_preferences',
        'local_borrowed_entries',
        'return_reminders',
        'sqlite_sequence',
      ]) {
        final expected = await live.query(table, orderBy: 'rowid');
        expect(expected, isNotEmpty, reason: table);
        expect(await db.query(table, orderBy: 'rowid'), expected,
            reason: table);
      }
      expect(restored.returnDate, DateTime(2026, 12, 12));
      final borrowed = await targetRepo.borrowedLoans();
      expect(borrowed.map((loan) => loan.origin),
          unorderedEquals(['qr', 'manual', 'sms']));
      final qr = borrowed.singleWhere((loan) => loan.origin == 'qr');
      expect(qr.returnDate, DateTime(2026, 12, 19));
      expect(qr.protocolSource!.returnDate, DateTime(2026, 12, 12));
      expect(notifications.pending.keys, [4]);
    }
    final file = await targetRepo.coverStorage.resolve(
      (await targetRepo.books()).single.coverUrl!,
    );
    expect(await file.parent.list().length, 1);
  });

  test('export waits for the in-flight repository cover write', () async {
    final observed = ObservedDatabase('${root.path}/source.db');
    source = observed;
    final storage = PausedCoverStorage(sourceSupport);
    final repository =
        LibraryRepository(database: source, coverStorage: storage);
    final image = await File('${root.path}/paused.jpg').writeAsBytes([1, 2]);
    final write = repository.addBook(
        title: 'W trakcie zapisu', author: 'Żaneta', coverUrl: image.path);
    await storage.entered.future;
    exporter =
        LibraryBackup(database: source, support: () async => sourceSupport);
    final preparing = prepare();
    try {
      await observed.exclusiveRequested.future;
      await expectLater(repository.addBook(title: 'Concurrent', author: 'A'),
          throwsStateError);
    } finally {
      storage.proceed.complete();
    }
    final saved = await write;
    await importer.restore(await preparing);
    final restored = (await targetRepo.books()).single;
    expect(restored.id, saved.id);
    expect(
        await (await targetRepo.coverStorage.resolve(restored.coverUrl!))
            .readAsBytes(),
        [1, 2]);
  });

  test('restore excludes concurrent repository writes and releases the gate',
      () async {
    await targetRepo.addBook(title: 'Old library', author: 'A');
    final incoming = await populate();
    final work = await prepare();
    final entered = Completer<void>();
    final proceed = Completer<void>();
    notifications.beforeInventory = () async {
      entered.complete();
      await proceed.future;
    };
    final restoring = importer.restore(work);
    try {
      await entered.future;
      await expectLater(targetRepo.addBook(title: 'Concurrent', author: 'A'),
          throwsStateError);
    } finally {
      proceed.complete();
    }
    await restoring;
    expect((await targetRepo.books()).single.id, incoming.id);
    await targetRepo.addBook(title: 'After restore', author: 'A');
    expect(await targetRepo.books(), hasLength(2));
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
    final oldImage =
        await File('${root.path}/original.jpg').writeAsBytes([9, 8]);
    final original = await targetRepo.addBook(
        title: 'Original', author: 'Author', coverUrl: oldImage.path);
    await targetRepo.savePreferredOwnerName('Stara biblioteka');
    final originalHistory = await (await target.database).query('history');
    final originalCover =
        await targetRepo.coverStorage.resolve(original.coverUrl!);
    final incoming = await populate();
    final work = await prepare();
    final staged = File('${work.path}/import/${incoming.coverUrl}');
    await staged.delete();
    final verifiedRollback = throwsA(isA<RestoreFailure>().having(
        (error) => error.previousLibraryVerified, 'previous library', true));
    await expectLater(importer.restore(work), verifiedRollback);
    expect((await targetRepo.books()).single.id, original.id);
    await staged.writeAsBytes([1, 3, 5, 7]);
    notifications.fail = true;
    await expectLater(importer.restore(work), verifiedRollback);
    expect((await targetRepo.books()).single.toMap(), original.toMap());
    expect(await targetRepo.preferredOwnerName(), 'Stara biblioteka');
    expect(await originalCover.readAsBytes(), [9, 8]);
    expect(await originalCover.parent.list().length, 1);
    final db = await target.database;
    expect(await db.query('history'), originalHistory);
    expect(await db.query('borrowed_loans'), isEmpty);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    await targetRepo.addBook(title: 'After rollback', author: 'Author');
    expect(await targetRepo.books(), hasLength(2));
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
