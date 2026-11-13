import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/data/library_repository.dart';
import 'package:my_library/main.dart';
import 'package:my_library/models/book.dart';

class RetryRepository extends LibraryRepository {
  final submittedIsbns = <String?>[];

  @override
  Future<Book> addBook({
    required String title,
    required String author,
    String description = '',
    String? coverUrl,
    String? barcode,
    String condition = 'Dobry',
    String genre = 'Bez gatunku',
  }) async {
    submittedIsbns.add(barcode);
    if (submittedIsbns.length == 1) throw const DuplicateIsbnException();
    final now = DateTime(2026, 11, 10);
    return Book(
      id: 'saved',
      title: title,
      author: author,
      barcode: barcode,
      createdAt: now,
      updatedAt: now,
    );
  }
}

void main() {
  testWidgets(
      'duplicate ISBN shows Polish feedback and corrected retry succeeds',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = RetryRepository();
    bool? added;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              added = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => AddBookScreen(repository: repository),
                ),
              );
            },
            child: const Text('Dodaj'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Dodaj'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Nowa książka');
    await tester.enterText(fields.at(1), 'Autor');
    await tester.enterText(fields.at(2), '978-0-525-55947-4');
    final save = find.widgetWithText(FilledButton, 'Zapisz książkę');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(
        find.text('Książka z tym numerem ISBN już istnieje.'), findsOneWidget);
    expect(find.byType(AddBookScreen), findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    expect(find.text('Nowa książka'), findsOneWidget);
    expect(added, isNull);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(fields.at(2));
    await tester.enterText(fields.at(2), '080442957X');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(repository.submittedIsbns, ['978-0-525-55947-4', '080442957X']);
    expect(added, isTrue);
    expect(find.byType(AddBookScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
