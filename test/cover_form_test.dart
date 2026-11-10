import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:my_library/data/library_repository.dart';
import 'package:my_library/main.dart';
import 'package:my_library/models/book.dart';
import 'package:my_library/services/cover_picker.dart';

class Picker extends CoverPicker {
  String? result;
  Completer<String?>? pending;
  final releases = <String?>[];
  ImageSource? source;
  @override
  Future<String?> pick(ImageSource source) async {
    this.source = source;
    return pending == null ? result : await pending!.future;
  }

  @override
  Future<void> releaseExcept([String? keep]) async => releases.add(keep);

  @override
  Future<String?> adjust(String path) async => result;
}

class Repository extends LibraryRepository {
  Completer<Book>? pendingSave;
  String? savedCover;
  bool? coverUpdated;
  Book result(String? cover) => Book(
      id: 'book',
      title: 'T',
      author: 'A',
      coverUrl: cover,
      createdAt: DateTime(2020),
      updatedAt: DateTime(2020));

  @override
  Future<Book> addBook(
      {required String title,
      required String author,
      String description = '',
      String? coverUrl,
      String? barcode,
      String condition = 'Dobry',
      String directory = 'Bez kategorii'}) async {
    savedCover = coverUrl;
    return result(coverUrl);
  }

  @override
  Future<Book> updateBook(
      {required String id,
      required String title,
      required String author,
      String? barcode,
      required String condition,
      String? coverUrl,
      bool updateCover = false}) async {
    savedCover = coverUrl;
    coverUpdated = updateCover;
    return pendingSave == null ? result(coverUrl) : await pendingSave!.future;
  }
}

void main() {
  testWidgets('leaving without saving releases draft and leaves book untouched',
      (tester) async {
    final repository = Repository();
    final picker = Picker()..result = '/temporary/cover.jpg';
    await tester.pumpWidget(MaterialApp(
        home: AddBookScreen(
            repository: repository,
            book: repository.result(null),
            coverPicker: picker)));
    await tester.tap(find.text('Wybierz zdjęcie z urządzenia'));
    await tester.pumpAndSettle();
    expect(picker.releases.last, '/temporary/cover.jpg');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(picker.releases.last, isNull);
    expect(repository.coverUpdated, isNull);
  });

  testWidgets('leaving during native selection releases late result',
      (tester) async {
    final repository = Repository();
    final picker = Picker()..pending = Completer<String?>();
    await tester.pumpWidget(MaterialApp(
        home: AddBookScreen(
            repository: repository,
            book: repository.result(null),
            coverPicker: picker)));
    await tester.tap(find.text('Wybierz zdjęcie z urządzenia'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    expect(picker.releases, isEmpty);
    picker.pending!.complete('/temporary/late.jpg');
    await tester.pumpAndSettle();
    expect(picker.releases.last, isNull);
    expect(repository.coverUpdated, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving during save retains source until the write completes',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = Repository()..pendingSave = Completer<Book>();
    final picker = Picker()..result = '/temporary/cover.jpg';
    await tester.pumpWidget(MaterialApp(
        home: AddBookScreen(
            repository: repository,
            book: repository.result(null),
            coverPicker: picker)));
    await tester.tap(find.text('Wybierz zdjęcie z urządzenia'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Zapisz zmiany'));
    await tester.pump();
    picker.releases.clear();
    await tester.pumpWidget(const SizedBox());
    expect(picker.releases, isEmpty);
    repository.pendingSave!.complete(repository.result('covers/saved.jpg'));
    await tester.pumpAndSettle();
    expect(picker.releases.last, isNull);
    expect(tester.takeException(), isNull);
  });

  for (final editing in [false, true]) {
    testWidgets(
        'shared form chooses camera/gallery, cancels, adjusts and saves (edit=$editing)',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = Repository();
      final picker = Picker();
      await tester.pumpWidget(MaterialApp(
          home: AddBookScreen(
              repository: repository,
              book: editing ? repository.result(null) : null,
              coverPicker: picker)));
      if (!editing) {
        await tester.enterText(find.byType(TextFormField).at(0), 'T');
        await tester.enterText(find.byType(TextFormField).at(1), 'A');
      }
      picker.result = '/temporary/gallery.jpg';
      await tester.tap(find.text('Wybierz zdjęcie z urządzenia'));
      await tester.pumpAndSettle();
      expect(picker.source, ImageSource.gallery);
      expect(find.text('Usuń okładkę'), findsOneWidget);
      picker.result = null;
      await tester.tap(find.text('Zrób zdjęcie'));
      await tester.pumpAndSettle();
      expect(picker.source, ImageSource.camera);
      expect(find.text('Usuń okładkę'), findsOneWidget);
      picker.result = '/temporary/cropped.jpg';
      await tester.tap(find.text('Przytnij i dopasuj'));
      await tester.pumpAndSettle();
      final save = find.widgetWithText(
          FilledButton, editing ? 'Zapisz zmiany' : 'Zapisz książkę');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(repository.savedCover, '/temporary/cropped.jpg');
      if (editing) expect(repository.coverUpdated, isTrue);
    });
  }

  testWidgets(
      'editing URL preserves cover on canceled pick and removes explicitly',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = Repository();
    await tester.pumpWidget(MaterialApp(
        home: AddBookScreen(
            repository: repository,
            book: repository.result('https://example.com/cover.jpg'),
            coverPicker: Picker())));
    await tester.tap(find.text('Wybierz zdjęcie z urządzenia'));
    await tester.pumpAndSettle();
    expect(find.text('Usuń okładkę'), findsOneWidget);
    await tester.tap(find.text('Usuń okładkę'));
    await tester.pumpAndSettle();
    expect(find.text('Usuń okładkę'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Zapisz zmiany'));
    await tester.pumpAndSettle();
    expect(repository.savedCover, isNull);
    expect(repository.coverUpdated, isTrue);
  });
}
