import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/data/library_repository.dart';
import 'package:my_library/main.dart';
import 'package:my_library/models/book.dart';

class DuplicateRepository extends LibraryRepository {
  int attempts = 0;

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
    attempts++;
    throw const DuplicateIsbnException();
  }
}

void main() {
  testWidgets('duplicate ISBN shows Polish feedback and allows retry',
      (tester) async {
    final repository = DuplicateRepository();
    await tester.pumpWidget(MaterialApp(
      home: AddBookScreen(repository: repository),
    ));
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Nowa książka');
    await tester.enterText(fields.at(1), 'Autor');
    await tester.enterText(fields.at(2), '978-0-525-55947-4');
    final save = find.widgetWithText(FilledButton, 'Zapisz książkę');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(find.text(DuplicateIsbnException.message), findsOneWidget);
    expect(find.byType(AddBookScreen), findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    expect(find.text('Nowa książka'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(repository.attempts, 2);
  });
}
