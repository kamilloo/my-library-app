import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/main.dart';
import 'package:my_library/screens/tutorial_screen.dart';
import 'package:my_library/screens/loan_messaging.dart';
import 'package:my_library/screens/offline_loans.dart';
import 'package:my_library/models/return_date.dart';
import 'offline_loans_test.dart' show WidgetRepository, fixture;

void main() {
  testWidgets('bottom navigation and borrowed heading display Pożyczone',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LibraryShell()));
    await tester.pump(const Duration(milliseconds: 300));
    final destination = find.byWidgetPredicate((widget) =>
        widget is NavigationDestination && widget.label == 'Pożyczone');
    expect(destination, findsOneWidget);
    await tester.tap(find.text('Pożyczone').last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Pożyczone'), findsNWidgets(2));
    expect(find.text('Pożyczone od innych'), findsNothing);
  });

  test('Help includes essential communication and local-copy limitations', () {
    final sms = loanHelpSections[0].description;
    for (final phrase in [
      'opłatami operatora',
      'polskie znaki',
      'wiele SMS-ów',
      'Udostępnij wiadomość',
      'Kopiuj wiadomość',
      'Wysyłasz wiadomość samodzielnie',
      'widoczna dla operatora',
      'nie zapewnia szyfrowania od końca do końca',
      'tożsamości nadawcy',
      'nie odczytuje SMS-ów automatycznie',
      'nie synchronizuje urządzeń',
      'potwierdzajcie bezpośrednio',
    ]) {
      expect(sms, contains(phrase));
    }
    final borrowing = loanHelpSections[1].description;
    for (final phrase in [
      'własną kopię',
      'Zapis właściciela jest rozstrzygający',
      'oddzielną lokalną kopię',
      'Daty i statusy nie synchronizują się',
      'QR importuje kopię',
      'SMS służy do komunikacji',
      'aktualizacja własnych lokalnych zapisów',
      'nie usuwa zapisu właściciela',
    ]) {
      expect(borrowing, contains(phrase));
    }
  });

  testWidgets('Help guidance is readable at 200 percent on a small screen',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
        child: child!,
      ),
      home: const LoanHelpScreen(),
    ));
    for (final section in loanHelpSections) {
      await tester.scrollUntilVisible(find.text(section.title), 150);
      await tester.scrollUntilVisible(find.text(section.description), 150);
      expect(find.text(section.description), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    final tutorial = find.text('Samouczek — 7 slajdów');
    await tester.scrollUntilVisible(tutorial, -150);
    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pumpAndSettle();
    await tester.tap(tutorial);
    await tester.pumpAndSettle();
    expect(find.text('1 / 7'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('operational screens omit static guidance and retain dates',
      (tester) async {
    final repository = WidgetRepository();
    final loan = fixture();
    final screens = <Widget>[
      const SmsMessageScreen(text: 'Wiadomość'),
      LoanQrScreen(loan: loan),
      Scaffold(body: BorrowedLoansScreen(repository: repository)),
      LoanMessagingScreen(repository: repository, loan: loan, ownerSide: false),
    ];
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final screen in screens) {
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data:
              MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: screen,
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('SMS może'), findsNothing);
      expect(find.textContaining('synchroniz'), findsNothing);
      expect(
          find.textContaining('Dane wypożyczenia są zapisywane'), findsNothing);
      expect(tester.takeException(), isNull);
    }
    expect(await repository.borrowedLoans(), isEmpty);
  });

  test('owned and borrowed dates share format and missing-date wording', () {
    expect(loanDate(DateTime(2026, 1, 3)), '03.01.2026');
    expect(loanDate(null), 'Brak terminu zwrotu');
    expect(loanDate(DateTime(2026, 1, 3)),
        returnDateHistoryValue(DateTime(2026, 1, 3)));
  });
}
