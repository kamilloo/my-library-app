import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/screens/support_screen.dart';
import 'package:my_library/screens/supporter_badge.dart';
import 'package:my_library/screens/tutorial_screen.dart';
import 'package:my_library/services/support_destination.dart';

const _destination = 'https://buycoffee.to/moja-biblioteka';
const _actionLabel = 'Wesprzyj projekt';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the bundled destination is the canonical clean HTTPS URL', () async {
    expect(await loadSupportDestination(), Uri.parse(_destination));
  });

  test('rejects unexpected or decorated support destinations', () {
    for (final value in [
      '',
      'http://buycoffee.to/moja-biblioteka',
      'https://buycoffee.to.evil.test/moja-biblioteka',
      'https://buycoffee.to@evil.test/moja-biblioteka',
      'https://user@buycoffee.to/moja-biblioteka',
      'https://buycoffee.to:443/moja-biblioteka',
      'https://buycoffee.to/',
      'https://buycoffee.to/moja-biblioteka/extra',
      'https://buycoffee.to/moja-biblioteka?utm_source=chatgpt.com',
      'https://buycoffee.to/moja-biblioteka#tip',
      'https://buycoffee.to/moja-biblioteka\n',
    ]) {
      expect(validateSupportDestination(value), isNull, reason: value);
    }
  });

  testWidgets('Help opens support and Back returns to the existing workflows',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoanHelpScreen()));
    expect(find.text('Kopia zapasowa'), findsOneWidget);
    expect(find.text('Samouczek — 7 slajdów'), findsOneWidget);
    await tester.tap(find.text(supportScreenTitle));
    await tester.pumpAndSettle();

    expect(find.text('Wesprzyj rozwój Mojej Biblioteki'), findsOneWidget);
    expect(
      find.text(
        'Moja Biblioteka jest darmową aplikacją do katalogowania książek i zarządzania wypożyczeniami.\n\n'
        'Jeśli aplikacja jest dla Ciebie przydatna, możesz dobrowolnie wesprzeć jej dalszy rozwój.\n\n'
        'Wsparcie jest całkowicie opcjonalne i nie wiąże się z żadnymi dodatkowymi korzyściami. Wszystkie funkcje aplikacji pozostają bezpłatne.',
      ),
      findsOneWidget,
    );
    expect(find.text('Dziękuję za każde wsparcie!'), findsOneWidget);
    expect(find.byType(SupporterBadgeImage), findsNothing);
    if (!kIsWeb) {
      expect(find.byWidgetPredicate((widget) => widget is FilledButton),
          findsNothing);
    }
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Pomoc'), findsOneWidget);
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));

  testWidgets('Android without billing shows the artwork and no checkout',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SupportScreen(
        loadAction: () async => throw StateError('Android opened BuyCoffee'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text(supportScreenTitle), findsOneWidget);
    expect(find.text('Wesprzyj rozwój Mojej Biblioteki'), findsOneWidget);
    final image = tester.widget<Image>(find.descendant(
      of: find.byType(SupporterBadgeImage),
      matching: find.byType(Image),
    ));
    expect((image.image as AssetImage).assetName, SupporterBadgeImage.asset);
    expect(
        find.textContaining('Zakup odznaki jest niedostępny'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('Przywróć zakup'), findsNothing);
  },
      variant: const TargetPlatformVariant({TargetPlatform.android}),
      skip: kIsWeb);

  for (final scale in [1.0, 2.0]) {
    testWidgets('small screen at text scale $scale works without network',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final opened = <Uri>[];
      final destination = validateSupportDestination(_destination)!;
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
          ),
          child: child!,
        ),
        home: SupportScreen(
          loadAction: () async => () => opened.add(destination),
        ),
      ));
      await tester.pumpAndSettle();

      expect(opened, isEmpty);
      final action = find.byWidgetPredicate((widget) => widget is FilledButton);
      await tester.scrollUntilVisible(action.hitTestable(), 100);
      await tester.pumpAndSettle();
      expect(find.text(_actionLabel), findsOneWidget);
      expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
      await tester.tap(action);
      expect(opened, [Uri.parse(_destination)]);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));
  }
}
