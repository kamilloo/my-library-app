import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/data/library_repository.dart';
import 'package:my_library/main.dart';
import 'package:my_library/models/book.dart';

class EditRepository extends LibraryRepository {
  Book book = Book(
      id: 'existing',
      title: 'Original',
      author: 'Author',
      barcode: '9780525559474',
      condition: 'Nowa',
      createdAt: DateTime(2020),
      updatedAt: DateTime(2020));
  int updates = 0;
  bool reject = false;

  @override
  Future<List<Book>> books() async => [book];

  @override
  Future<Book> updateBook(
      {required String id,
      required String title,
      required String author,
      String? barcode,
      required String condition,
      String? coverUrl,
      String? genre,
      bool updateCover = false}) async {
    if (reject) throw const DuplicateIsbnException();
    expect(id, book.id);
    updates++;
    book = Book.fromMap({
      ...book.toMap(),
      'title': title,
      'author': author,
      'barcode': barcode,
      'condition': condition
    });
    return book;
  }
}

void main() {
  for (final cancel in [false, true]) {
    testWidgets(
        cancel
            ? 'cancel leaves book and history unchanged'
            : 'edit refreshes details and library without adding a book or history',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = EditRepository();
      final before = repository.book.toMap();
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: LibraryScreen(repository: repository))));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BookCard));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edytuj książkę'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      expect(find.text('Original'), findsOneWidget);
      expect(find.text('Author'), findsOneWidget);
      expect(find.text('9780525559474'), findsOneWidget);
      expect(find.text('Nowa'), findsOneWidget);
      await tester.enterText(fields.at(0), '');
      final save = find.widgetWithText(FilledButton, 'Zapisz zmiany');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('Wpisz tytuł'), findsOneWidget);
      await tester.enterText(fields.at(0), 'Corrected');
      await tester.enterText(fields.at(1), 'Corrected author');
      if (cancel) {
        await tester.pageBack();
      } else {
        repository.reject = true;
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(find.text(DuplicateIsbnException.message), findsOneWidget);
        expect(find.byType(AddBookScreen), findsOneWidget);
        expect(repository.updates, 0);
        repository.reject = false;
        await tester.enterText(fields.at(2), '080442957X');
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Zużyta').last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        await tester.tap(save);
      }
      await tester.pumpAndSettle();
      expect(find.byType(BookDetailsScreen), findsOneWidget);
      expect(find.text(cancel ? 'Original' : 'Corrected'), findsWidgets);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text(cancel ? 'Original' : 'Corrected'), findsWidgets);
      expect(repository.book.id, before['id']);
      expect(repository.updates, cancel ? 0 : 1);
      if (cancel) expect(repository.book.toMap(), before);
      expect(tester.takeException(), isNull);
    });
  }
}
