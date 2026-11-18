import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/models/loan_transfer.dart';
import 'package:my_library/screens/offline_loans.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  final loan = LoanTransfer(
    transferId: 'transfer',
    loanId: 'loan',
    bookId: 'book',
    title: 'Zażółć gęślą jaźń',
    author: 'Łukasz Ćma',
    borrowedAt: DateTime(2026, 1, 2),
    issuedAt: DateTime.utc(2026, 1, 3),
    revision: 1,
  );

  testWidgets('QR displays the invitation with a close action', (tester) async {
    await tester.pumpWidget(
        MaterialApp(home: LoanQrScreen(loan: loan, borrower: 'Czytelnik')));
    expect(find.text(loan.title), findsOneWidget);
    expect(find.text('Właściciel: Nie podano'), findsOneWidget);
    expect(find.text('Wypożyczono: Czytelnik'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Zamknij'), 120);
    expect(find.text('Zamknij'), findsOneWidget);
    expect(find.text('Udostępnij informacje'), findsNothing);
    expect(find.text('Kopiuj kod'), findsNothing);
  });
}
