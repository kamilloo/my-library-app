import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/data/library_repository.dart';
import 'package:my_library/models/loan_transfer.dart';
import 'package:my_library/models/book.dart';
import 'package:my_library/models/readable_loan.dart';
import 'package:my_library/screens/borrowed_entry.dart';
import 'package:my_library/screens/loan_messaging.dart';
import 'package:my_library/screens/offline_loans.dart';
import 'readable_loan_test.dart' show text, today, invitation;

class EntryRepository extends LibraryRepository {
  EntryRepository() : super(clock: () => today);
  ReadableLoan? saved;
  String? origin, source;
  DateTime? changed;
  int ownerExtensions = 0;
  String? extendedBook;
  @override
  Future<Book> approveReadableExtension(LoanTransfer loan, DateTime date) =>
      extendLoan(loan.bookId, date);
  @override
  Future<Book> extendLoan(String id, DateTime date) async {
    ownerExtensions++;
    extendedBook = id;
    changed = date;
    return Book(
        id: id,
        title: 'Wiedźmin',
        author: 'Andrzej Sapkowski',
        createdAt: today,
        updatedAt: today,
        returnDate: date);
  }

  @override
  Future<LoanTransfer> loanInvitation(String id) async => invitation();
  @override
  Future<String> saveLocalBorrowed(ReadableLoan input,
      {required String origin, String? smsSource}) async {
    saved = input.validated();
    this.origin = origin;
    source = smsSource;
    return 'local';
  }

  @override
  Future<List<LoanTransfer>> borrowedLoans() async => [invitation()];
  @override
  Future<List<Map<String, Object?>>> messages(String role,
          {String? loanId}) async =>
      [];
  @override
  Future<String?> contact(String role, String loanId) async => null;
  @override
  Future<void> changeBorrowedDueDate(LoanTransfer loan, DateTime date) async {
    changed = date;
  }
}

Widget app(Widget screen) => MaterialApp(
    locale: const Locale('pl'),
    supportedLocales: const [Locale('pl')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate
    ],
    home: screen);
void main() {
  Future<void> large(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets('all three actions coexist above the same borrowed list',
      (tester) async {
    await large(tester);
    await tester.pumpWidget(app(
        Scaffold(body: BorrowedLoansScreen(repository: EntryRepository()))));
    await tester.pumpAndSettle();
    for (final label in [
      'Skanuj kod QR',
      'Dodaj z SMS',
      'Dodaj ręcznie',
      'Wiedźmin'
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });
  testWidgets(
      'SMS preview saves every correction only after explicit confirmation',
      (tester) async {
    await large(tester);
    final repo = EntryRepository();
    await tester
        .pumpWidget(app(BorrowedEntryScreen(repository: repo, fromSms: true)));
    await tester.enterText(find.byType(TextField), text);
    await tester.tap(find.text('Odczytaj wiadomość'));
    await tester.pumpAndSettle();
    expect(repo.saved, isNull);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Poprawiony tytuł');
    await tester.enterText(fields.at(1), 'Poprawiony autor');
    await tester.enterText(fields.at(2), 'Poprawiony właściciel');
    await tester.enterText(fields.at(3), '9780306406157');
    await tester.tap(find.text('Termin zwrotu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Potwierdź i zapisz'));
    await tester.pumpAndSettle();
    expect(repo.saved!.title, 'Poprawiony tytuł');
    expect(repo.saved!.author, 'Poprawiony autor');
    expect(repo.saved!.owner, 'Poprawiony właściciel');
    expect(repo.saved!.isbn, '9780306406157');
    expect(repo.saved!.returnDate, today);
    expect(repo.source, text);
    expect(repo.origin, 'sms');
  });
  testWidgets('manual date defaults today and optional due can be cleared',
      (tester) async {
    await large(tester);
    final repo = EntryRepository();
    await tester
        .pumpWidget(app(BorrowedEntryScreen(repository: repo, fromSms: false)));
    expect(find.text('16.11.2026'), findsOneWidget);
    expect(find.text('Brak terminu zwrotu'), findsOneWidget);
    await tester.tap(find.text('Potwierdź i zapisz'));
    await tester.pumpAndSettle();
    expect(repo.saved, isNull);
    expect(find.textContaining('Uzupełnij poprawnie'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await tester.enterText(
          find.byType(TextField).at(i), ['Tytuł', 'Autor', 'Właściciel'][i]);
    }
    await tester.tap(find.text('Termin zwrotu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usuń termin zwrotu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Potwierdź i zapisz'));
    await tester.pumpAndSettle();
    expect(repo.saved!.borrowedAt, today);
    expect(repo.saved!.returnDate, isNull);
    expect(repo.origin, 'manual');
    expect(repo.source, isNull);
  });
  testWidgets(
      'borrower local due change requires confirmation, request does not change record',
      (tester) async {
    await large(tester);
    final repo = EntryRepository();
    await tester.pumpWidget(app(LoanMessagingScreen(
        repository: repo, loan: invitation(), ownerSide: false)));
    await tester.pumpAndSettle();
    expect(find.text('Wklej potwierdzenie przedłużenia'), findsNothing);
    await tester.tap(find.text('Zmień termin zwrotu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(repo.changed, isNull);
    await tester.tap(find.text('Anuluj'));
    await tester.pumpAndSettle();
    expect(repo.changed, isNull);
    await tester.tap(find.text('Zmień termin zwrotu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Potwierdź'));
    await tester.pumpAndSettle();
    expect(repo.changed, DateTime(2026, 12, 14));
    expect(repo.ownerExtensions, 0);
  });
  testWidgets('readable borrower request never changes saved due date',
      (tester) async {
    await large(tester);
    final repo = EntryRepository();
    await tester.pumpWidget(app(LoanMessagingScreen(
        repository: repo, loan: invitation(), ownerSide: false)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Poproś o przedłużenie'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('21'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Przygotowana wiadomość'), findsOneWidget);
    final message =
        tester.widget<SelectableText>(find.byType(SelectableText)).data!;
    expect(message, contains('Moja Biblioteka — prośba o przedłużenie'));
    expect(message, contains('Proponowany termin zwrotu: 21.12.2026'));
    expect(message, isNot(contains('moja-biblioteka:')));
    expect(repo.changed, isNull);
    expect(repo.ownerExtensions, 0);
  });
  testWidgets('owner approval targets the current owned book action',
      (tester) async {
    await large(tester);
    final repo = EntryRepository();
    await tester.pumpWidget(app(LoanMessagingScreen(
        repository: repo, loan: invitation(), ownerSide: true)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zatwierdź przedłużenie'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('21'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(repo.ownerExtensions, 1);
    expect(repo.extendedBook, 'owned-book');
    expect(repo.changed, DateTime(2026, 12, 21));
    expect(find.text('Przygotowana wiadomość'), findsOneWidget);
  });
}
