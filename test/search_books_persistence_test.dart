import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_library/data/library_database.dart';
import 'package:my_library/data/library_repository.dart';
import 'package:my_library/main.dart';
import 'package:my_library/models/book.dart';
import 'package:my_library/services/open_library_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class SearchPersistenceRepository extends LibraryRepository {
  SearchPersistenceRepository(LibraryDatabase database)
      : super(database: database);
  int inserts = 0;
  // Run real SQLite I/O in runAsync, outside the widget test's fake clock.
  Future<Book> Function()? write;
  final result = Completer<Book>();
  @override
  Future<Book> addBook({
    required String title,
    required String author,
    String description = '',
    String? coverUrl,
    String? barcode,
    String condition = 'Dobry',
    String directory = 'Bez kategorii',
  }) async {
    inserts++;
    write = () => super.addBook(
        title: title,
        author: author,
        description: description,
        coverUrl: coverUrl,
        barcode: barcode,
        condition: condition,
        directory: directory);
    return result.future;
  }
}

void main() {
  setUpAll(sqfliteFfiInit);
  for (final duplicate in [false, true]) {
    testWidgets(
        'search selection/save with SQLite restart and existing loan isolation: duplicate=$duplicate',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      late Directory temp;
      late Database db;
      late LibraryDatabase database;
      late Map<String, Object?> originalRow;
      late List<Map<String, Object?>> originalHistory;
      await tester.runAsync(() async {
        temp = await Directory.systemTemp.createTemp('search-persistence-');
        database =
            LibraryDatabase.file(databaseFactoryFfi, '${temp.path}/library.db');
        db = await database.database;
        final seed = LibraryRepository(database: database);
        final book = await seed.addBook(
            title: 'Existing',
            author: 'Original author',
            barcode: '080442957X');
        await seed.lendBook(book, 'Anna', DateTime(2030));
        originalRow = (await db.query('books')).single;
        originalHistory = await db.query('history', orderBy: 'id');
      });
      final repository = SearchPersistenceRepository(database);
      final service = OpenLibraryService(
          client: MockClient((_) async => http.Response(
              jsonEncode({
                'docs': [
                  {
                    'title': 'Found title',
                    'author_name': ['Found author'],
                    'cover_i': 42,
                    'key': duplicate ? '/books/OL1M' : '/works/OL1W',
                    'edition_key': ['OL1M'],
                    'isbn': ['080442957X'],
                  }
                ],
              }),
              200)));
      try {
        await tester.pumpWidget(MaterialApp(
            home: AddBookScreen(repository: repository, isbnService: service)));
        await tester.tap(find.text('Szukaj książki po tytule lub autorze'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'Find');
        await tester.tap(find.widgetWithText(FilledButton, 'Szukaj'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Wybierz książkę'));
        await tester.pumpAndSettle();
        expect(repository.inserts, 0);
        await tester.runAsync(() async {
          expect(await db.query('books'), [originalRow]);
          expect(await db.query('history', orderBy: 'id'), originalHistory);
        });
        await tester.enterText(
            find.byType(TextFormField).first, 'Corrected title');
        final save = find.widgetWithText(FilledButton, 'Zapisz książkę');
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        expect(
            tester
                .widget<TextFormField>(find.byType(TextFormField).at(1))
                .controller!
                .text,
            'Found author');
        await tester.tap(save);
        expect(repository.inserts, 1);
        await tester.runAsync(() async {
          try {
            repository.result.complete(await repository.write!());
          } catch (error, stack) {
            repository.result.completeError(error, stack);
          }
        });
        await tester.pumpAndSettle();
        expect(repository.inserts, 1);
        if (duplicate) {
          expect(find.text(DuplicateIsbnException.message), findsOneWidget);
          expect(find.byType(AddBookScreen), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          final originalId = originalRow['id'];
          expect(
              (await db
                      .query('books', where: 'id = ?', whereArgs: [originalId]))
                  .single,
              originalRow);
          expect(
              await db.query('history',
                  where: 'book_id = ?', whereArgs: [originalId], orderBy: 'id'),
              originalHistory);
          await db.close();
          final reopened = LibraryDatabase.file(
              databaseFactoryFfi, '${temp.path}/library.db');
          db = await reopened.database;
          final rows = await db.query('books');
          expect(rows, hasLength(duplicate ? 1 : 2));
          if (!duplicate) {
            final added = rows.singleWhere((row) => row['id'] != originalId);
            expect(added['title'], 'Corrected title');
            expect(added['author'], 'Found author');
            expect(added['cover_url'],
                'https://covers.openlibrary.org/b/id/42-M.jpg');
            expect(added['barcode'], isNull);
            expect(added['status'], 'available');
            final history = await db.query('history',
                where: 'book_id = ?', whereArgs: [added['id']]);
            expect(history, hasLength(1));
            expect(history.single['action'], 'added');
          }
        });
      } finally {
        await tester.runAsync(() async {
          await db.close();
          await temp.delete(recursive: true);
        });
      }
    });
  }
}
