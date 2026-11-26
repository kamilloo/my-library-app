import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:my_library/data/library_repository.dart';
import 'package:my_library/main.dart';
import 'package:my_library/models/book.dart';
import 'package:my_library/models/genre.dart';
import 'package:my_library/models/return_date.dart';
import 'package:my_library/models/loan_transfer.dart';
import 'package:my_library/screens/genres.dart';
import 'package:my_library/screens/main_screen_header.dart';
import 'package:my_library/screens/offline_loans.dart';
import 'package:my_library/screens/supporter_badge.dart';
import 'package:my_library/screens/tutorial_screen.dart';
import 'package:my_library/services/supporter_billing.dart';

import 'supporter_billing_test.dart' show FakePlay, purchase;

class ScreenRepository extends LibraryRepository {
  final date = DateTime(2025, 2, 10);
  bool hasLoan = true;
  bool hasHistory = true;
  int extraHistoryEntries = 0;
  String author = 'Łukasz Żak';

  @override
  Future<List<Genre>> genres() async => [const Genre('f', 'Fantastyka', 1)];

  @override
  Future<List<Book>> books() async => [
        Book(
          id: 'owned',
          title: 'Świat',
          author: author,
          genre: 'Fantastyka',
          status: BookStatus.available,
          createdAt: date,
          updatedAt: date,
        ),
      ];

  @override
  Future<List<HistoryEntry>> history() async => [
        if (hasHistory) ...[
          HistoryEntry(
            id: '2',
            bookId: 'owned',
            bookTitle: 'Świat',
            action: 'returned',
            detail: 'Zwrot książki',
            timestamp: date,
          ),
          HistoryEntry(
            id: '1',
            bookId: 'deleted',
            bookTitle: 'Świat dawniej',
            action: 'added',
            detail: 'Dodano książkę',
            timestamp: date.subtract(const Duration(days: 1)),
          ),
          for (var i = 0; i < extraHistoryEntries; i++)
            HistoryEntry(
              id: 'older-$i',
              bookId: 'owned',
              bookTitle: 'Świat — $i',
              action: 'added',
              timestamp: date.subtract(Duration(days: i + 2)),
            ),
        ],
      ];

  @override
  Future<List<LoanTransfer>> borrowedLoans() async => [
        if (hasLoan)
          LoanTransfer(
            transferId: 'transfer',
            loanId: 'loan',
            bookId: 'borrowed',
            title: 'Łąka',
            author: 'Jan Śliwa',
            owner: 'Żaneta Łącka',
            borrowedAt: date,
            issuedAt: date,
            revision: 1,
          ),
      ];

  @override
  Future<void> deleteBorrowedLoan(String loanId, {String origin = 'qr'}) async {
    hasLoan = false;
  }
}

Future<void> showScreen(WidgetTester tester, Widget screen,
    {bool largeText = false}) async {
  await tester.pumpWidget(MaterialApp(
    builder: largeText
        ? (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            )
        : null,
    home: Scaffold(body: screen),
  ));
  await tester.pumpAndSettle();
}

Future<void> search(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pumpAndSettle();
}

void main() {
  final screens = <String, Widget Function(ScreenRepository)>{
    'Moje książki': (repo) => LibraryScreen(repository: repo),
    'Historia': (repo) => HistoryScreen(repository: repo),
    'Pożyczone': (repo) => BorrowedLoansScreen(repository: repo),
  };

  for (final confirmedPurchase in [false, true]) {
    testWidgets(
        'all main tabs update the badge with ${confirmedPurchase ? 'confirmed Play ownership' : 'simulation only'}',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final play = FakePlay();
      addTearDown(play.events.close);
      var billingCreations = 0;
      final repo = ScreenRepository();
      final tabs = [for (final screen in screens.values) screen(repo)];
      var selected = 0;
      await tester.pumpWidget(SupporterBillingScope.forApp(
        debug: true,
        testFlag: true,
        licenseTestFlag: true,
        web: false,
        platform: TargetPlatform.android,
        createBilling: () {
          billingCreations++;
          return SupporterBilling(play);
        },
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: IndexedStack(index: selected, children: tabs),
              bottomNavigationBar: NavigationBar(
                selectedIndex: selected,
                onDestinationSelected: (index) =>
                    setState(() => selected = index),
                destinations: [
                  for (final title in screens.keys)
                    NavigationDestination(
                      icon: const Icon(Icons.book_outlined),
                      label: title,
                    ),
                ],
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final header = find.byType(MainScreenHeader);
      final badge = find.descendant(
        of: header,
        matching: find.byType(SupporterBadgeImage),
      );
      final help = find.byType(TutorialHelpButton);
      SupporterBillingProvider scope() =>
          SupporterBillingScope.of(tester.element(header))!;

      Future<void> checkTabs(bool showBadge) async {
        for (final title in screens.keys) {
          await tester.tap(find.widgetWithText(NavigationDestination, title));
          await tester.pumpAndSettle();
          expect(find.descendant(of: header, matching: find.text(title)),
              findsOneWidget);
          expect(badge, showBadge ? findsOneWidget : findsNothing);
          expect(help.hitTestable(), findsOneWidget);
          if (showBadge) {
            final image = find.descendant(
              of: badge,
              matching: find.byType(Image),
            );
            final widget = tester.widget<Image>(image);
            expect((widget.image as AssetImage).assetName,
                'assets/supporter/przyjaciel_biblioteki.png');
            expect(widget.fit, BoxFit.contain);
            expect(widget.semanticLabel, contains('Przyjaciel Biblioteki'));
            expect(tester.getRect(badge).right,
                closeTo(tester.getRect(help).left - 4, 0.01));
            expect(tester.getCenter(badge).dy, tester.getCenter(help).dy);
          }
          expect(tester.takeException(), isNull);
        }
      }

      await checkTabs(false);
      if (confirmedPurchase) {
        play.purchases = [
          purchase(PurchaseStatus.purchased, needsAcknowledgment: false),
        ];
        scope().setEnabled!(true);
        await tester.pumpAndSettle();
        expect(scope().billing?.owned, isTrue);
        await checkTabs(true);
      }

      final queries = play.ownershipQueries;
      scope().setSimulatedSupporterOwned!(true);
      await tester.pump();
      expect(badge, findsOneWidget);
      await checkTabs(true);
      await tester.tap(find.text('Pomoc'));
      await tester.pumpAndSettle();
      expect(find.byType(LoanHelpScreen), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();

      scope().setSimulatedSupporterOwned!(false);
      await tester.pump();
      expect(badge, confirmedPurchase ? findsOneWidget : findsNothing);
      await checkTabs(confirmedPurchase);
      expect(billingCreations, confirmedPurchase ? 1 : 0);
      expect(play.availabilityChecks, confirmedPurchase ? 1 : 0);
      expect(play.requestedIds, confirmedPurchase ? [supporterProductId] : []);
      expect(queries, confirmedPurchase ? 1 : 0);
      expect(play.ownershipQueries, queries);
      expect(play.launches, 0);
      expect(play.acknowledgmentAttempts, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final entry in screens.entries) {
    testWidgets('${entry.key} has a shared header and Help on a small screen',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await showScreen(tester, entry.value(ScreenRepository()),
          largeText: true);
      expect(find.byType(MainScreenHeader), findsOneWidget);
      expect(find.text(entry.key), findsOneWidget);
      expect(find.byType(SearchBar), findsOneWidget);
      expect(find.text('Moja biblioteka'), findsNothing);
      expect(find.text('1 książek w kolekcji'), findsNothing);
      expect(find.text('Twoje książki'), findsNothing);
      expect(find.text('Zarządzaj gatunkami'), findsNothing);
      expect(find.text('Wszystkie zmiany zapisane lokalnie'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Pomoc'));
      await tester.pumpAndSettle();
      expect(find.text('Wyszukiwanie i gatunki'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('library genre heading opens the selector', (tester) async {
    final repo = ScreenRepository();
    await showScreen(tester, LibraryScreen(repository: repo));
    expect(find.widgetWithText(GenreSelector, 'Wszystkie gatunki'),
        findsOneWidget);
    await tester.tap(find.byType(GenreSelector));
    await tester.pumpAndSettle();
    expect(find.text('Zarządzaj gatunkami'), findsOneWidget);
    await tester.tap(find.text('Fantastyka'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(GenreSelector, 'Fantastyka'), findsOneWidget);
    final book = find.byType(BookCard);
    expect(book, findsOneWidget);

    await search(tester, 'lukasz');
    expect(book, findsOneWidget);
    repo.author = 'Anna';
    await showScreen(
        tester, LibraryScreen(repository: repo, refreshRevision: 1));
    expect(
        find.text('Brak książek pasujących do wyszukiwania.'), findsOneWidget);
    expect(find.widgetWithText(GenreSelector, 'Fantastyka'), findsOneWidget);
    await search(tester, 'Anna');
    expect(book, findsOneWidget);
  });

  testWidgets(
      'history matches titles and current authors and keeps event order',
      (tester) async {
    final repo = ScreenRepository();
    await showScreen(tester, HistoryScreen(repository: repo));
    await search(tester, 'SWIAT');
    expect(find.text('Świat'), findsOneWidget);
    expect(find.text('Świat dawniej'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Świat')).dy,
        lessThan(tester.getTopLeft(find.text('Świat dawniej')).dy));
    expect(find.text('Zwrot książki'), findsOneWidget);
    expect(find.text(formatReturnDate(repo.date)), findsOneWidget);
    expect(find.text('Dodano książkę'), findsOneWidget);
    await search(tester, 'LUKASZ Z\u0307AK');
    expect(find.text('Świat'), findsOneWidget);
    expect(find.text('Świat dawniej'), findsNothing);

    await showScreen(tester, HistoryScreen(repository: repo, active: false));
    repo.author = 'Anna';
    await showScreen(tester, HistoryScreen(repository: repo));
    expect(
        find.text('Brak wpisów pasujących do wyszukiwania.'), findsOneWidget);
    await search(tester, 'ANNA');
    expect(find.text('Świat'), findsOneWidget);

    repo.hasHistory = false;
    await showScreen(
        tester, HistoryScreen(repository: repo, refreshRevision: 2));
    expect(find.text('Brak historii wypożyczeń.'), findsOneWidget);
  });

  testWidgets('search text survives scrolling the header out of view',
      (tester) async {
    final repo = ScreenRepository()..extraHistoryEntries = 32;
    await showScreen(tester, HistoryScreen(repository: repo));
    await search(tester, 'swiat');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    final field = find.byType(EditableText).hitTestable();
    final list = find.byType(ListView);
    await tester.drag(list, const Offset(0, -1100));
    await tester.pumpAndSettle();
    expect(field, findsNothing);
    await tester.drag(list, const Offset(0, 1300));
    await tester.pumpAndSettle();
    expect(tester.widget<EditableText>(field).controller.text, 'swiat');
  });

  testWidgets('borrowed search matches title, author and Polish owner names',
      (tester) async {
    await showScreen(
        tester, BorrowedLoansScreen(repository: ScreenRepository()));
    for (final query in [
      'ŁĄKA',
      'jan sliwa',
      '  ZANETA LACKA  ',
      'ŻANETA ŁĄCKA'
    ]) {
      await search(tester, query);
      expect(find.text('Łąka'), findsOneWidget);
    }
    await search(tester, 'missing');
    expect(find.text('Łąka'), findsNothing);
    expect(find.text('Brak pożyczonych książek pasujących do wyszukiwania.'),
        findsOneWidget);
    await search(tester, 'żaneta');
    await tester.tap(find.byTooltip('Usuń lokalny zapis'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Usuń'));
    await tester.pumpAndSettle();
    expect(find.text('Brak pożyczonych książek.'), findsOneWidget);
    expect(find.text('Łąka'), findsNothing);
  });
}
