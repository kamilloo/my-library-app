import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/data/library_repository.dart';
import 'package:my_library/main.dart';
import 'package:my_library/models/book.dart';

class FilterRepository extends LibraryRepository {
  @override
  Future<List<Book>> books() async => [
        for (final status in BookStatus.values)
          for (final title in ['Zebra', 'Atlas'])
            Book(
              id: '${status.name}-$title',
              title: '$title ${status.name}',
              author: title == 'Atlas' ? 'Anna' : 'Jan',
              status: status,
              createdAt: DateTime(2020),
              updatedAt: DateTime(2020),
            ),
      ];
}

void main() {
  testWidgets('all status filters combine with title/author search and sorting',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: LibraryScreen(repository: FilterRepository())),
    ));
    await tester.pumpAndSettle();

    List<String> visibleIds() => tester
        .widgetList<BookCard>(find.byType(BookCard))
        .map((card) => card.book.id)
        .toList();

    final filters = {
      'Wszystkie': null,
      'Dostępne': BookStatus.available,
      'Wypożyczone': BookStatus.borrowed,
      'Oddane na stałe': BookStatus.given,
    };
    for (final entry in filters.entries) {
      final chip = find.widgetWithText(FilterChip, entry.key);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(chip).selected, isTrue);
      final statuses = entry.value == null ? BookStatus.values : [entry.value!];
      expect(visibleIds(), [
        for (final status in statuses)
          for (final title in ['Zebra', 'Atlas']) '${status.name}-$title',
      ]);
      for (final query in ['aTlAs', 'aNNa', 'missing']) {
        await tester.enterText(find.byType(TextField), query);
        await tester.pumpAndSettle();
        expect(
            visibleIds(),
            query == 'missing'
                ? <String>[]
                : [for (final status in statuses) '${status.name}-Atlas']);
        if (query == 'missing') {
          expect(find.text('Brak książek pasujących do wyszukiwania.'),
              findsOneWidget);
        }
        expect(find.text('6 książek w kolekcji'), findsOneWidget);
      }
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Sortuj A–Z'));
      await tester.pumpAndSettle();
      final sorted = visibleIds();
      expect(sorted.first, contains('Atlas'));
      expect(sorted.last, contains('Zebra'));
      expect(tester.widget<FilterChip>(chip).selected, isTrue);
      await tester.tap(find.byTooltip('Sortuj według ostatnio dodanych'));
      await tester.pumpAndSettle();
    }
  });
}
