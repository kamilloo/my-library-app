import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/data/library_repository.dart';
import 'package:my_library/main.dart';
import 'package:my_library/models/book.dart';
import 'package:my_library/models/return_date.dart';

class DateRepository extends LibraryRepository {
  DateRepository(this.book);
  Book book;
  bool fail = false;
  int saves = 0;
  final events = <HistoryEntry>[];

  @override
  Future<List<HistoryEntry>> historyForBook(String bookId) async => events;

  @override
  Future<Book> updateReturnDate(String bookId, DateTime? date) async {
    if (fail) throw StateError('disk unavailable');
    expect(bookId, book.id);
    saves++;
    final old = book.returnDate;
    book = Book.fromMap({
      ...book.toMap(),
      'return_date': date?.toIso8601String(),
      'updated_at':
          book.updatedAt.add(const Duration(seconds: 1)).toIso8601String(),
    });
    events.add(HistoryEntry(
        id: '$saves',
        bookId: book.id,
        bookTitle: book.title,
        action: 'return_date_changed',
        detail:
            'Zmieniono termin zwrotu: ${returnDateHistoryValue(old)} → ${returnDateHistoryValue(date)}',
        timestamp: DateTime.now()));
    return book;
  }
}

void main() {
  Book borrowed(DateTime? due, {BookStatus status = BookStatus.borrowed}) =>
      Book(
          id: 'book',
          title: 'Title',
          author: 'Author',
          status: status,
          borrowedBy: 'Anna',
          borrowedDate: DateTime(2020),
          returnDate: due,
          createdAt: DateTime(2020),
          updatedAt: DateTime(2020));

  Future<void> open(WidgetTester tester, DateRepository repository) async {
    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('pl'),
      supportedLocales: const [Locale('pl')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: BookDetailsScreen(book: repository.book, repository: repository),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> edit(WidgetTester tester) async {
    final action = find.widgetWithText(TextButton, 'Zmień termin zwrotu');
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'saved date selected; save refreshes details and history without reminder service',
      (tester) async {
    final due = DateTime(DateTime.now().year + 1, 11, 20);
    final repository = DateRepository(borrowed(due));
    await open(tester, repository);
    expect(
        find.text('Termin zwrotu: ${formatReturnDate(due)}'), findsOneWidget);
    await edit(tester);
    expect(
        tester
            .widget<DatePickerDialog>(find.byType(DatePickerDialog))
            .initialDate,
        due);
    await tester.tap(find.text('30'));
    await tester.tap(find.text('Zapisz'));
    await tester.pumpAndSettle();
    final changed = DateTime(due.year, 11, 30);
    expect(repository.saves, 1);
    expect(find.text('Termin zwrotu: ${formatReturnDate(changed)}'),
        findsOneWidget);
    expect(find.text('Zmieniono termin zwrotu'), findsOneWidget);
    expect(find.textContaining('20.11.${due.year} → 30.11.${due.year}'),
        findsOneWidget);
    expect(repository.book.borrowedBy, 'Anna');
    expect(repository.book.status, BookStatus.borrowed);
  });

  testWidgets('explicit clear confirms and refreshes missing-date state',
      (tester) async {
    final due = DateTime(DateTime.now().year + 1, 11, 20);
    final repository = DateRepository(borrowed(due));
    await open(tester, repository);
    await tester.tap(find.text('Usuń termin zwrotu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anuluj'));
    await tester.pumpAndSettle();
    expect(repository.saves, 0);
    await tester.tap(find.text('Usuń termin zwrotu'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Usuń termin'));
    await tester.pumpAndSettle();
    expect(find.text('Nie ustawiono terminu zwrotu'), findsOneWidget);
    expect(find.text('Usuń termin zwrotu'), findsNothing);
    expect(repository.book.returnDate, isNull);
  });

  testWidgets('first date can be set and picker cancellation does not save',
      (tester) async {
    final repository = DateRepository(borrowed(null));
    await open(tester, repository);
    expect(find.text('Nie ustawiono terminu zwrotu'), findsOneWidget);
    await edit(tester);
    final dialog =
        tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
    final today = calendarDate(DateTime.now());
    expect(dialog.initialDate, today);
    await tester.tap(find.text('Anuluj'));
    await tester.pumpAndSettle();
    expect(repository.saves, 0);
    await edit(tester);
    await tester.tap(find.text('Zapisz'));
    await tester.pumpAndSettle();
    expect(
        find.text('Termin zwrotu: ${formatReturnDate(today)}'), findsOneWidget);
    expect(repository.saves, 1);
  });

  testWidgets(
      'overdue saved date stays selected; other past dates are disabled',
      (tester) async {
    final today = calendarDate(DateTime.now());
    final saved = today.subtract(const Duration(days: 5));
    final repository = DateRepository(borrowed(saved));
    await open(tester, repository);
    await edit(tester);
    final dialog =
        tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
    expect(dialog.initialDate, saved);
    expect(dialog.selectableDayPredicate!(saved), isTrue);
    expect(
        dialog.selectableDayPredicate!(today.subtract(const Duration(days: 1))),
        isFalse);
    expect(dialog.selectableDayPredicate!(today), isTrue);
  });

  testWidgets('save error retains date and shows Polish retry feedback',
      (tester) async {
    final due = DateTime(DateTime.now().year + 1, 11, 20);
    final repository = DateRepository(borrowed(due))..fail = true;
    await open(tester, repository);
    await edit(tester);
    await tester.tap(find.text('30'));
    await tester.tap(find.text('Zapisz'));
    await tester.pumpAndSettle();
    expect(
        find.text('Termin zwrotu: ${formatReturnDate(due)}'), findsOneWidget);
    expect(find.text('Nie udało się zmienić terminu zwrotu. Spróbuj ponownie.'),
        findsOneWidget);
    repository.fail = false;
    await edit(tester);
    await tester.tap(find.text('30'));
    await tester.tap(find.text('Zapisz'));
    await tester.pumpAndSettle();
    expect(repository.saves, 1);
  });

  for (final status in [BookStatus.available, BookStatus.given]) {
    testWidgets('date action hidden for ${status.name}', (tester) async {
      await open(tester, DateRepository(borrowed(null, status: status)));
      expect(find.text('Zmień termin zwrotu'), findsNothing);
      expect(find.text('Usuń termin zwrotu'), findsNothing);
    });
  }
}
