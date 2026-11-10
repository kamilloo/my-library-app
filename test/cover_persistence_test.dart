import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/data/library_database.dart';
import 'package:my_library/data/library_repository.dart';
import 'package:my_library/services/cover_storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class AlwaysFailingCleanupStorage extends CoverStorage {
  AlwaysFailingCleanupStorage(Directory root)
      : super(directory: () async => Directory('${root.path}/support'));
  @override
  Future<void> delete(String? reference) async =>
      throw StateError('Cleanup unavailable');
}

class FailingCleanupStorage extends CoverStorage {
  FailingCleanupStorage(Directory root)
      : super(directory: () async => Directory('${root.path}/support'));
  String? failReference;
  final deleted = <String?>[];

  @override
  Future<void> delete(String? reference) async {
    deleted.add(reference);
    if (reference == failReference) {
      throw StateError('Unexpected cleanup failure');
    }
    await super.delete(reference);
  }
}

class PausingCoverStorage extends CoverStorage {
  PausingCoverStorage(Directory root)
      : super(directory: () async => Directory('${root.path}/support'));
  bool pause = false;
  final staged = Completer<String?>();
  final resume = Completer<void>();
  @override
  Future<String?> persist(String? reference) async {
    final result = await super.persist(reference);
    if (pause) {
      staged.complete(result);
      await resume.future;
    }
    return result;
  }
}

void main() {
  late Directory root;
  late LibraryDatabase database;
  late LibraryRepository repository;
  late CoverStorage storage;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    root = await Directory.systemTemp.createTemp('library-covers');
    storage =
        CoverStorage(directory: () async => Directory('${root.path}/support'));
    database =
        LibraryDatabase.file(databaseFactoryFfi, '${root.path}/books.db');
    repository = LibraryRepository(database: database, coverStorage: storage);
  });
  tearDown(() async {
    await (await database.database).close();
    await root.delete(recursive: true);
  });

  Future<String> image() async {
    final file = File('${root.path}/temporary.jpg');
    await file.writeAsBytes([1, 2, 3, 4]);
    return file.path;
  }

  test('URL and absent references survive metadata edits and restart',
      () async {
    for (final reference in [
      null,
      'https://covers.openlibrary.org/b/id/123-L.jpg'
    ]) {
      final book = await repository.addBook(
          title: 'Book', author: 'Author', coverUrl: reference);
      final edited = await repository.updateBook(
          id: book.id, title: 'Edited', author: 'Author', condition: 'Dobry');
      expect(edited.coverUrl, reference);
    }
    await (await database.database).close();
    database =
        LibraryDatabase.file(databaseFactoryFfi, '${root.path}/books.db');
    repository = LibraryRepository(database: database, coverStorage: storage);
    expect((await repository.books()).map((b) => b.coverUrl),
        containsAll([null, 'https://covers.openlibrary.org/b/id/123-L.jpg']));
  });

  test('save copies picker file; reopen resolves portable reference offline',
      () async {
    final source = await image();
    final book = await repository.addBook(
        title: 'Book', author: 'Author', coverUrl: source);
    expect(CoverStorage.isManaged(book.coverUrl!), isTrue);
    expect(book.coverUrl, isNot(source));
    await File(source).delete();
    await (await database.database).close();
    database =
        LibraryDatabase.file(databaseFactoryFfi, '${root.path}/books.db');
    storage =
        CoverStorage(directory: () async => Directory('${root.path}/support'));
    repository = LibraryRepository(database: database, coverStorage: storage);
    final restored = (await repository.books()).single;
    expect(restored.coverUrl, book.coverUrl);
    expect(await (await storage.resolve(restored.coverUrl!)).readAsBytes(),
        [1, 2, 3, 4]);
    final rows = await (await database.database).query('books');
    expect(rows.single['cover_url'], isA<String>());
  });

  test(
      'replace and remove retain shared covers until last reference disappears',
      () async {
    final first = await repository.addBook(
        title: 'First', author: 'A', coverUrl: await image());
    final shared = await repository.addBook(
        title: 'Second', author: 'A', coverUrl: first.coverUrl);
    final old = await storage.resolve(first.coverUrl!);
    final replacement = await repository.updateBook(
        id: first.id,
        title: 'First',
        author: 'A',
        condition: 'Dobry',
        updateCover: true,
        coverUrl: await image());
    expect(await old.exists(), isTrue);
    expect(replacement.coverUrl, isNot(first.coverUrl));
    await repository.deleteBook(shared.id);
    expect(await old.exists(), isFalse);
    final newFile = await storage.resolve(replacement.coverUrl!);
    await repository.updateBook(
        id: first.id,
        title: 'First',
        author: 'A',
        condition: 'Dobry',
        updateCover: true,
        coverUrl: null);
    expect(await newFile.exists(), isFalse);
    expect((await repository.books()).single.coverUrl, isNull);
  });

  test('failed edit cleans copied file and preserves existing cover', () async {
    final first = await repository.addBook(
        title: 'First', author: 'A', barcode: '111', coverUrl: await image());
    await repository.addBook(title: 'Other', author: 'A', barcode: '222');
    await expectLater(
        repository.updateBook(
            id: first.id,
            title: 'First',
            author: 'A',
            barcode: '222',
            condition: 'Dobry',
            updateCover: true,
            coverUrl: await image()),
        throwsA(isA<DuplicateIsbnException>()));
    final files =
        await Directory('${root.path}/support/covers').list().toList();
    expect(files, hasLength(1));
    expect(await (await storage.resolve(first.coverUrl!)).exists(), isTrue);
  });

  test('committed replacement succeeds even when old-cover cleanup throws',
      () async {
    final failing = FailingCleanupStorage(root);
    repository = LibraryRepository(database: database, coverStorage: failing);
    final first = await repository.addBook(
        title: 'First', author: 'A', coverUrl: await image());
    failing.failReference = first.coverUrl;
    final saved = await repository.updateBook(
        id: first.id,
        title: 'Saved',
        author: 'A',
        condition: 'Dobry',
        updateCover: true,
        coverUrl: await image());
    final row = (await (await database.database).query('books')).single;
    expect(row['title'], 'Saved');
    expect(row['cover_url'], saved.coverUrl);
    expect(await (await storage.resolve(saved.coverUrl!)).exists(), isTrue);
    expect(failing.deleted, [first.coverUrl]);
    expect(await (await storage.resolve(first.coverUrl!)).exists(), isTrue);
  });

  test(
      'failed update transaction rolls back metadata and removes only new copy',
      () async {
    final first = await repository.addBook(
        title: 'First', author: 'A', coverUrl: await image());
    final db = await database.database;
    final before = await db.query('books');
    final history = await db.query('history');
    await db.execute(
        "CREATE TRIGGER reject_edit BEFORE UPDATE ON books BEGIN SELECT RAISE(ABORT, 'rejected edit'); END");
    await expectLater(
        repository.updateBook(
            id: first.id,
            title: 'Changed',
            author: 'A',
            condition: 'Dobry',
            updateCover: true,
            coverUrl: await image()),
        throwsA(isA<DatabaseException>()));
    expect(await db.query('books'), before);
    expect(await db.query('history'), history);
    expect(await Directory('${root.path}/support/covers').list().length, 1);
    expect(await (await storage.resolve(first.coverUrl!)).exists(), isTrue);
  });

  test(
      'failed add transaction removes copy and leaves no book or history reference',
      () async {
    final db = await database.database;
    await db.execute(
        "CREATE TRIGGER reject_history BEFORE INSERT ON history BEGIN SELECT RAISE(ABORT, 'rejected history'); END");
    final source = await image();
    await expectLater(
        repository.addBook(title: 'First', author: 'A', coverUrl: source),
        throwsA(isA<DatabaseException>()));
    expect(await db.query('books'), isEmpty);
    expect(await db.query('history'), isEmpty);
    expect(await Directory('${root.path}/support/covers').list().length, 0);
    expect(await File(source).exists(), isTrue);
  });

  test(
      'rollback cleanup failure preserves transaction error and existing reference',
      () async {
    final failing = FailingCleanupStorage(root);
    repository = LibraryRepository(database: database, coverStorage: failing);
    final first = await repository.addBook(
        title: 'First', author: 'A', coverUrl: await image());
    final db = await database.database;
    await db.execute(
        "CREATE TRIGGER reject_edit BEFORE UPDATE ON books BEGIN SELECT RAISE(ABORT, 'rejected edit'); END");
    // Make every cleanup throw, including for the newly copied cover.
    final unavailable = AlwaysFailingCleanupStorage(root);
    repository =
        LibraryRepository(database: database, coverStorage: unavailable);
    await expectLater(
        repository.updateBook(
            id: first.id,
            title: 'Changed',
            author: 'A',
            condition: 'Dobry',
            updateCover: true,
            coverUrl: await image()),
        throwsA(isA<DatabaseException>()));
    expect((await db.query('books')).single['cover_url'], first.coverUrl);
    expect(await (await storage.resolve(first.coverUrl!)).exists(), isTrue);
  });

  test('deleting shared cover keeps it until last book is deleted', () async {
    final first = await repository.addBook(
        title: 'First', author: 'A', coverUrl: await image());
    final second = await repository.addBook(
        title: 'Second', author: 'A', coverUrl: first.coverUrl);
    final file = await storage.resolve(first.coverUrl!);
    await repository.deleteBook(first.id);
    expect(await file.exists(), isTrue);
    expect((await (await database.database).query('books')).single['cover_url'],
        second.coverUrl);
    await repository.deleteBook(second.id);
    expect(await file.exists(), isFalse);
    expect(await (await database.database).query('books'), isEmpty);
  });

  test(
      'delete commits despite cleanup failure; failed delete retains its cover',
      () async {
    final failing = FailingCleanupStorage(root);
    repository = LibraryRepository(database: database, coverStorage: failing);
    final first = await repository.addBook(
        title: 'First', author: 'A', coverUrl: await image());
    final db = await database.database;
    await db.execute(
        "CREATE TRIGGER reject_delete BEFORE DELETE ON books BEGIN SELECT RAISE(ABORT, 'rejected delete'); END");
    await expectLater(
        repository.deleteBook(first.id), throwsA(isA<DatabaseException>()));
    expect(await (await storage.resolve(first.coverUrl!)).exists(), isTrue);
    expect((await db.query('books')).single['cover_url'], first.coverUrl);
    expect(failing.deleted, isEmpty);
    await db.execute('DROP TRIGGER reject_delete');
    failing.failReference = first.coverUrl;
    await repository.deleteBook(first.id);
    expect(await db.query('books'), isEmpty);
  });

  test('removing a cover preserves metadata lending state and history',
      () async {
    final first = await repository.addBook(
        title: 'First',
        author: 'A',
        barcode: '111',
        description: 'Description',
        directory: 'Shelf',
        condition: 'Nowa',
        coverUrl: await image());
    await repository.lendBook(first, 'Borrower', DateTime(2030));
    final db = await database.database;
    final before = Map<String, Object?>.from((await db.query('books')).single);
    final history = await db.query('history');
    await repository.updateBook(
        id: first.id,
        title: 'First',
        author: 'A',
        barcode: '111',
        condition: 'Nowa',
        updateCover: true);
    final after = Map<String, Object?>.from((await db.query('books')).single);
    expect(after.remove('cover_url'), isNull);
    before.remove('cover_url');
    before.remove('updated_at');
    after.remove('updated_at');
    expect(after, before);
    expect(await db.query('history'), history);
    expect(await (await storage.resolve(first.coverUrl!)).exists(), isFalse);
  });

  test('failed edit never cleans an existing shared managed reference',
      () async {
    final first = await repository.addBook(
        title: 'First', author: 'A', barcode: '111', coverUrl: await image());
    final second =
        await repository.addBook(title: 'Second', author: 'A', barcode: '222');
    await expectLater(
        repository.updateBook(
            id: second.id,
            title: 'Second',
            author: 'A',
            barcode: '111',
            condition: 'Dobry',
            updateCover: true,
            coverUrl: first.coverUrl),
        throwsA(isA<DuplicateIsbnException>()));
    expect(await (await storage.resolve(first.coverUrl!)).exists(), isTrue);
    final rows = await (await database.database)
        .query('books', where: 'id = ?', whereArgs: [second.id]);
    expect(rows.single['cover_url'], isNull);
  });

  test(
      'deletion during staged cover edit cannot resurrect book or leave the new copy referenced',
      () async {
    final pausing = PausingCoverStorage(root);
    repository = LibraryRepository(
        database: database,
        coverStorage: pausing,
        clock: () => DateTime(2026, 11, 10));
    final book = await repository.addBook(
        title: 'Book', author: 'A', coverUrl: await image());
    final source = await image();
    pausing.pause = true;
    final edit = repository.updateBook(
        id: book.id,
        title: 'Stale edit',
        author: 'A',
        condition: 'Dobry',
        updateCover: true,
        coverUrl: source);
    final rejected = expectLater(edit, throwsStateError);
    final staged = await pausing.staged.future;
    expect(await (await pausing.resolve(staged!)).exists(), isTrue);
    await repository.deleteBook(book.id);
    pausing.resume.complete();
    await rejected;
    final db = await database.database;
    expect(await db.query('books'), isEmpty);
    expect(await db.query('history'), isEmpty);
    expect(await (await pausing.resolve(staged)).exists(), isFalse);
    expect(await File(source).exists(), isTrue);
  });

  test(
      'copy failure during cover replacement preserves previous reference and file',
      () async {
    final book = await repository.addBook(
        title: 'Book', author: 'A', coverUrl: await image());
    final db = await database.database;
    final before = await db.query('books');
    final history = await db.query('history');
    await expectLater(
        repository.updateBook(
            id: book.id,
            title: 'Changed',
            author: 'A',
            condition: 'Dobry',
            updateCover: true,
            coverUrl: '${root.path}/missing-input.jpg'),
        throwsA(isA<FileSystemException>()));
    expect(await db.query('books'), before);
    expect(await db.query('history'), history);
    expect(await (await storage.resolve(book.coverUrl!)).readAsBytes(),
        [1, 2, 3, 4]);
    expect(await Directory('${root.path}/support/covers').list().length, 1);
  });

  test('cleanup never deletes external files', () async {
    final source = await image();
    await storage.delete(source);
    await storage.delete('covers/../../temporary.jpg');
    expect(await File(source).exists(), isTrue);
  });
}
