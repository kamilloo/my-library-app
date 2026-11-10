import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/data/library_repository.dart';
import 'package:my_library/main.dart';
import 'package:my_library/models/book.dart';
import 'package:my_library/models/return_date.dart';

class ExtensionRepository extends LibraryRepository {
  ExtensionRepository(this.book)
      : super(clock: () => DateTime(2026, 11, 10, 12));
  Book book;
  int calls = 0;
  bool fail = false;
  Completer<void>? pending;
  final events = <HistoryEntry>[];
  @override
  Future<List<Book>> books() async => [book];
  @override
  Future<List<HistoryEntry>> historyForBook(String bookId) async => events;
  @override
  Future<Book> extendLoan(String bookId, DateTime date) async {
    calls++;
    if (pending != null) await pending!.future;
    if (fail) throw StateError('storage unavailable');
    final old = book.returnDate;
    book = Book.fromMap({
      ...book.toMap(),
      'return_date': date.toIso8601String(),
      'updated_at':
          book.updatedAt.add(const Duration(seconds: 1)).toIso8601String(),
    });
    events.add(HistoryEntry(
        id: '$calls',
        bookId: book.id,
        bookTitle: book.title,
        action: 'loan_extended',
        detail:
            'Przedłużono wypożyczenie: ${returnDateHistoryValue(old)} → ${formatReturnDate(date)}',
        timestamp: currentTime));
    return book;
  }
}

void main() {
  final due = DateTime(2027, 11, 20);
  Book fixture(DateTime? date, {BookStatus status = BookStatus.borrowed}) =>
      Book(
          id: 'book',
          title: 'Title',
          author: 'Author',
          status: status,
          borrowedBy: 'Anna',
          borrowedDate: DateTime(2020, 2, 3),
          returnDate: date,
          createdAt: DateTime(2020),
          updatedAt: DateTime(2020));

  Future<void> open(WidgetTester tester, ExtensionRepository repo) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('pl'),
      supportedLocales: const [Locale('pl')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: LibraryScreen(repository: repo)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BookCard));
    await tester.pumpAndSettle();
  }

  Future<void> extend(WidgetTester tester) async {
    final action = find.widgetWithText(TextButton, 'Przedłuż wypożyczenie');
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
  }

  final confirm = find.widgetWithText(FilledButton, 'Potwierdź prolongatę');

  for (final days in [7, 14, 30]) {
    testWidgets('+$days preview confirmation and detail/history/list refresh',
        (tester) async {
      final repo = ExtensionRepository(fixture(due));
      await open(tester, repo);
      expect(find.text('Wypożyczono: Anna'), findsOneWidget);
      expect(find.text('Data wypożyczenia: 03.02.2020'), findsOneWidget);
      await extend(tester);
      expect(
          find.text('Obecny termin: ${formatReturnDate(due)}'), findsOneWidget);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.tap(find.widgetWithText(ChoiceChip, '+$days dni'));
      await tester.pumpAndSettle();
      final newDate = extendedReturnDate(due, days);
      expect(find.text('Nowy termin zwrotu: ${formatReturnDate(newDate)}'),
          findsOneWidget);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(repo.calls, 1);
      expect(find.text('Termin zwrotu: ${formatReturnDate(newDate)}'),
          findsOneWidget);
      expect(
          find.text(
              'Przedłużono wypożyczenie do ${formatReturnDate(newDate)}.'),
          findsOneWidget);
      expect(find.text('Przedłużono wypożyczenie'), findsOneWidget);
      expect(repo.book.borrowedBy, 'Anna');
      expect(repo.book.borrowedDate, DateTime(2020, 2, 3));
      Navigator.of(tester.element(find.byType(BookDetailsScreen))).pop();
      await tester.pumpAndSettle();
      expect(tester.widget<BookCard>(find.byType(BookCard)).book.returnDate,
          newDate);
      expect(find.text('Termin zwrotu: ${formatReturnDate(newDate)}'),
          findsOneWidget);
    });
  }

  for (final hasDate in [true, false]) {
    testWidgets('custom date selection works with existing date: $hasDate',
        (tester) async {
      final repo = ExtensionRepository(fixture(hasDate ? due : null));
      await open(tester, repo);
      await extend(tester);
      if (!hasDate) {
        for (final days in [7, 14, 30]) {
          expect(
              tester
                  .widget<ChoiceChip>(
                      find.widgetWithText(ChoiceChip, '+$days dni'))
                  .onSelected,
              isNull);
        }
        expect(find.textContaining('Bez obecnej daty'), findsOneWidget);
      }
      await tester.tap(find.text('Wybierz datę'));
      await tester.pumpAndSettle();
      final picker =
          tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
      expect(picker.firstDate.isAfter(DateTime(2026, 11, 10)), isTrue);
      if (hasDate) expect(picker.firstDate, extendedReturnDate(due, 1));
      await tester.tap(find.text('Wybierz'));
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(repo.calls, 1);
      expect(repo.book.returnDate, picker.firstDate);
    });
  }

  testWidgets('overdue preset that remains past cannot be confirmed',
      (tester) async {
    final old = extendedReturnDate(DateTime(2026, 11, 10), -20);
    final repo = ExtensionRepository(fixture(old));
    await open(tester, repo);
    await extend(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, '+7 dni'));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Nowy termin zwrotu: ${formatReturnDate(extendedReturnDate(old, 7))}'),
        findsOneWidget);
    expect(find.text('Termin prolongaty musi przypadać po dzisiejszym dniu.'),
        findsOneWidget);
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.tap(find.widgetWithText(ChoiceChip, '+30 dni'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(repo.calls, 1);
    expect(repo.book.returnDate, extendedReturnDate(old, 30));
  });

  testWidgets('repeated confirmation taps submit once while saving',
      (tester) async {
    final repo = ExtensionRepository(fixture(due))..pending = Completer<void>();
    await open(tester, repo);
    await extend(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, '+14 dni'));
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.tap(confirm);
    await tester.pump();
    expect(repo.calls, 1);
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    repo.pending!.complete();
    await tester.pumpAndSettle();
    expect(repo.events, hasLength(1));
  });

  testWidgets('storage failure preserves preview and allows explicit retry',
      (tester) async {
    final repo = ExtensionRepository(fixture(due))..fail = true;
    await open(tester, repo);
    await extend(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, '+14 dni'));
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(
        find.text('Nie udało się przedłużyć wypożyczenia. Spróbuj ponownie.'),
        findsOneWidget);
    expect(
        find.text(
            'Nowy termin zwrotu: ${formatReturnDate(extendedReturnDate(due, 14))}'),
        findsOneWidget);
    expect(repo.book.returnDate, due);
    repo.fail = false;
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(repo.events, hasLength(1));
  });

  for (final status in [BookStatus.available, BookStatus.given]) {
    testWidgets('extension action hidden for ${status.name}', (tester) async {
      await open(tester, ExtensionRepository(fixture(due, status: status)));
      expect(find.text('Przedłuż wypożyczenie'), findsNothing);
    });
  }
}
