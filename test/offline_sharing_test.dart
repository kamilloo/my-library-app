import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/models/loan_transfer.dart';
import 'package:my_library/screens/offline_loans.dart';

void main() {
  const channel = MethodChannel('my_library/offline_loans');
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

  testWidgets(
      'user sharing passes only the invitation and installation guidance',
      (tester) async {
    MethodCall? shared;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      shared = call;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(MaterialApp(
        home: LoanQrScreen(loan: loan, borrower: 'Private borrower')));
    await tester.scrollUntilVisible(find.text('Udostępnij informacje'), 300);
    await tester.tap(find.text('Udostępnij informacje'));
    await tester.pumpAndSettle();
    expect(shared!.method, 'share');
    final text = (shared!.arguments as Map)['text'] as String;
    expect(text, contains(loan.encode()));
    expect(text, contains('Potrzebujesz aplikacji Moja Biblioteka'));
    expect(text, contains('Po instalacji'));
    expect(text, contains('Wklej kod wypożyczenia'));
    expect(text, isNot(contains('Private borrower')));
    expect(text, isNot(contains('https://')));
  });

  testWidgets('native sharing failure retains the manual copy fallback',
      (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (_) async {
      throw PlatformException(code: 'unavailable');
    });
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    await tester.pumpWidget(MaterialApp(home: LoanQrScreen(loan: loan)));
    await tester.scrollUntilVisible(find.text('Udostępnij informacje'), 300);
    await tester.tap(find.text('Udostępnij informacje'));
    await tester.pumpAndSettle();
    expect(find.text('Nie udało się udostępnić informacji. Użyj „Kopiuj kod”.'),
        findsOneWidget);
    await tester.scrollUntilVisible(find.text('Kopiuj kod'), 100);
    await tester.tap(find.text('Kopiuj kod'));
    await tester.pumpAndSettle();
    expect(copied, loan.encode());
    expect(tester.takeException(), isNull);
  });
}
