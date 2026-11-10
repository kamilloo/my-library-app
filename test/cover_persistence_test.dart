import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/data/library_database.dart';
import 'package:my_library/data/library_repository.dart';
import 'package:my_library/services/cover_storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

  test('cleanup never deletes external files', () async {
    final source = await image();
    await storage.delete(source);
    await storage.delete('covers/../../temporary.jpg');
    expect(await File(source).exists(), isTrue);
  });
}
