import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:my_library/screens/support_screen.dart';
import 'package:my_library/screens/supporter_badge.dart';
import 'package:my_library/screens/tutorial_screen.dart';
import 'package:my_library/services/library_backup.dart';
import 'package:my_library/services/supporter_billing.dart';

PurchaseDetails purchase(
  PurchaseStatus status, {
  String id = supporterProductId,
  String token = 'play-test-token',
  bool needsAcknowledgment = true,
}) =>
    PurchaseDetails(
      productID: id,
      verificationData: PurchaseVerificationData(
        localVerificationData: '',
        serverVerificationData: token,
        source: 'google_play',
      ),
      transactionDate: null,
      status: status,
    )..pendingCompletePurchase = needsAcknowledgment;

class FakePlay implements SupporterStore {
  final events = StreamController<List<PurchaseDetails>>.broadcast();
  final requestedIds = <String>[];
  bool available = true;
  bool hasProduct = true;
  bool ownershipError = false;
  bool acknowledgmentError = false;
  bool launchSucceeds = true;
  int launches = 0;
  int acknowledgmentAttempts = 0;
  List<PurchaseDetails> purchases = [];
  Completer<void>? acknowledgmentGate;

  @override
  Stream<List<PurchaseDetails>> get updates => events.stream;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<ProductDetails?> product(String id) async {
    requestedIds.add(id);
    if (!hasProduct) return null;
    return ProductDetails(
      id: id,
      title: 'Przyjaciel Biblioteki',
      description: 'Testowa odznaka',
      price: '2,49 €',
      rawPrice: 2.49,
      currencyCode: 'EUR',
    );
  }

  @override
  Future<List<PurchaseDetails>> ownedPurchases() async {
    if (ownershipError) throw StateError('store connection lost');
    return purchases;
  }

  @override
  Future<bool> buy(ProductDetails product) async {
    launches++;
    return launchSucceeds;
  }

  @override
  Future<void> acknowledge(PurchaseDetails purchase) async {
    acknowledgmentAttempts++;
    await acknowledgmentGate?.future;
    if (acknowledgmentError) throw StateError('acknowledgment failed');
  }
}

Future<void> flushEvents() => Future<void>.delayed(Duration.zero);

Finder buyButton(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((widget) => widget is FilledButton),
    );

final testSwitch =
    find.widgetWithText(SwitchListTile, 'Testowanie zakupów Google Play');

Widget testBillingApp(FakePlay store, Widget home) =>
    SupporterBillingScope.forApp(
      createBilling: () => SupporterBilling(store),
      debug: true,
      testFlag: true,
      web: false,
      platform: TargetPlatform.android,
      child: MaterialApp(home: home),
    );

Future<void> toggleTesting(WidgetTester tester) async {
  await tester.ensureVisible(testSwitch);
  await tester.tap(testSwitch);
  await tester.pumpAndSettle();
}

Future<FakePlay> mountSupport(WidgetTester tester, Widget screen,
    {bool available = true, bool enable = true}) async {
  final store = FakePlay()..available = available;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await store.events.close();
  });
  await tester.pumpWidget(testBillingApp(store, screen));
  await tester.pumpAndSettle();
  if (enable) await toggleTesting(tester);
  return store;
}

void main() {
  late FakePlay store;
  late SupporterBilling billing;

  setUp(() {
    store = FakePlay();
    billing = SupporterBilling(store);
  });

  tearDown(() async {
    if (store.events.hasListener) billing.dispose();
    await store.events.close();
  });

  test('only native Android debug with the test flag enables billing', () {
    for (final (debug, flag, web, platform, enabled) in [
      (true, true, false, TargetPlatform.android, true),
      (false, true, false, TargetPlatform.android, false),
      (true, false, false, TargetPlatform.android, false),
      (true, true, true, TargetPlatform.android, false),
      (true, true, false, TargetPlatform.iOS, false),
    ]) {
      expect(
        isSupporterBillingEnabled(
          debug: debug,
          testFlag: flag,
          web: web,
          platform: platform,
        ),
        enabled,
      );
    }
  });

  for (final (name, debug, flag, web, platform) in [
    ('production or profile', false, true, false, TargetPlatform.android),
    ('Safari', true, true, true, TargetPlatform.iOS),
    (
      'Android debug without the flag',
      true,
      false,
      false,
      TargetPlatform.android
    ),
  ]) {
    testWidgets('billing switch is absent in $name', (tester) async {
      await tester.pumpWidget(SupporterBillingScope.forApp(
        createBilling: () => throw StateError('Billing initialized in $name'),
        debug: debug,
        testFlag: flag,
        web: web,
        platform: platform,
        child: MaterialApp(home: SupportScreen(loadAction: () async => () {})),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.text('Tryb deweloperski'), findsNothing);
      expect(find.text('Przywróć zakup'), findsNothing);
    });
  }

  testWidgets('switch starts OFF, initializes Play on demand and stops it',
      (tester) async {
    final play =
        await mountSupport(tester, const SupportScreen(), enable: false);
    final button = buyButton('Kup odznakę — 2,49 €');
    expect(tester.widget<SwitchListTile>(testSwitch).value, isFalse);
    expect(play.events.hasListener, isFalse);
    expect(play.requestedIds, isEmpty);
    expect(button, findsNothing);

    await toggleTesting(tester);
    expect(tester.widget<SwitchListTile>(testSwitch).value, isTrue);
    expect(play.events.hasListener, isTrue);
    expect(play.requestedIds, [supporterProductId]);
    expect(play.launches, 0);
    expect(play.acknowledgmentAttempts, 0);
    expect(find.text('Przyjaciel Biblioteki'), findsNothing);
    final staleBuy = tester.widget<FilledButton>(button).onPressed!;

    await toggleTesting(tester);
    expect(tester.widget<SwitchListTile>(testSwitch).value, isFalse);
    expect(play.events.hasListener, isFalse);
    expect(button, findsNothing);
    expect(find.text('Przywróć zakup'), findsNothing);
    staleBuy();
    play.events.add([purchase(PurchaseStatus.purchased)]);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(play.requestedIds, [supporterProductId]);
    expect(play.launches, 0);
    expect(play.acknowledgmentAttempts, 0);

    await toggleTesting(tester);
    expect(play.events.hasListener, isTrue);
    expect(play.requestedIds, [supporterProductId, supporterProductId]);
    expect(button, findsOneWidget);
  });

  testWidgets(
      'switch stays locked through checkout, pending and acknowledgment',
      (tester) async {
    final play = await mountSupport(tester, const SupportScreen());
    final disable = tester.widget<SwitchListTile>(testSwitch).onChanged!;
    final button = buyButton('Kup odznakę — 2,49 €');

    Future<void> expectLocked() async {
      expect(tester.widget<SwitchListTile>(testSwitch).onChanged, isNull);
      disable(false);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(testSwitch).value, isTrue);
      expect(play.events.hasListener, isTrue);
      expect(find.text('Przyjaciel Biblioteki'), findsNothing);
    }

    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(play.launches, 1);
    await expectLocked();

    play.purchases = [purchase(PurchaseStatus.pending)];
    play.events.add(play.purchases);
    await tester.pumpAndSettle();
    await expectLocked();

    play.ownershipError = true;
    final restore = find.text('Przywróć zakup');
    await tester.ensureVisible(restore);
    await tester.tap(restore);
    await tester.pumpAndSettle();
    await expectLocked();

    play.ownershipError = false;
    play.acknowledgmentGate = Completer<void>();
    play.purchases = [purchase(PurchaseStatus.purchased)];
    play.events.add(play.purchases);
    await tester.pumpAndSettle();
    expect(play.acknowledgmentAttempts, 1);
    await expectLocked();

    play.acknowledgmentGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Przyjaciel Biblioteki'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(testSwitch).onChanged, isNotNull);
    await toggleTesting(tester);
    expect(play.events.hasListener, isFalse);
  });

  test('queries only the configured product and loads the localized price',
      () async {
    expect(billing.status, SupporterStatus.initializing);
    await billing.refresh();
    expect(store.requestedIds, [supporterProductId]);
    expect(billing.product?.price, '2,49 €');
    expect(billing.owned, isFalse);
    expect(billing.canBuy, isTrue);
  });

  test('store unavailable and inactive product both block checkout', () async {
    store.available = false;
    await billing.refresh();
    expect(billing.status, SupporterStatus.storeUnavailable);
    await billing.buy();
    store.available = true;
    store.hasProduct = false;
    await billing.refresh();
    expect(billing.status, SupporterStatus.productUnavailable);
    await billing.buy();
    expect(store.launches, 0);
  });

  test('rapid taps launch once and cancellation grants nothing', () async {
    await billing.refresh();
    await Future.wait([billing.buy(), billing.buy(), billing.buy()]);
    expect(store.launches, 1);
    expect(billing.canRestore, isFalse);
    store.events.add([purchase(PurchaseStatus.canceled, id: '', token: '')]);
    await flushEvents();
    expect(billing.status, SupporterStatus.canceled);
    expect(billing.owned, isFalse);
    expect(billing.canBuy, isTrue);
  });

  test('failed launch and failed payment are retryable', () async {
    await billing.refresh();
    store.launchSucceeds = false;
    await billing.buy();
    expect(billing.status, SupporterStatus.purchaseFailed);
    store.launchSucceeds = true;
    await billing.buy();
    store.events.add([purchase(PurchaseStatus.error, id: '')]);
    await flushEvents();
    expect(billing.status, SupporterStatus.purchaseFailed);
    expect(billing.owned, isFalse);
    expect(billing.canBuy, isTrue);
  });

  test('pending payment becomes owned after confirmation and acknowledgment',
      () async {
    await billing.refresh();
    await billing.buy();
    store.purchases = [purchase(PurchaseStatus.pending)];
    store.events.add(store.purchases);
    await flushEvents();
    expect(billing.status, SupporterStatus.pending);
    expect(billing.canBuy, isFalse);
    expect(billing.owned, isFalse);
    expect(store.acknowledgmentAttempts, 0);

    store.acknowledgmentGate = Completer<void>();
    store.purchases = [purchase(PurchaseStatus.purchased)];
    store.events.add(store.purchases);
    store.events.add(store.purchases);
    await flushEvents();
    expect(billing.status, SupporterStatus.verifying);
    expect(billing.owned, isFalse);
    store.acknowledgmentGate!.complete();
    await flushEvents();
    expect(billing.status, SupporterStatus.owned);
    expect(billing.owned, isTrue);
    expect(store.acknowledgmentAttempts, 1);
    await billing.buy();
    expect(store.launches, 1);
  });

  test(
      'unrelated products, missing tokens and unconfirmed tokens grant nothing',
      () async {
    await billing.refresh();
    store.events
        .add([purchase(PurchaseStatus.purchased, id: 'another_product')]);
    await flushEvents();
    expect(billing.status, SupporterStatus.available);
    store.events.add([purchase(PurchaseStatus.purchased, token: ' ')]);
    await flushEvents();
    expect(billing.status, SupporterStatus.verificationRejected);
    store.purchases = [
      purchase(PurchaseStatus.purchased, token: 'another-token')
    ];
    store.events.add([purchase(PurchaseStatus.purchased)]);
    await flushEvents();
    expect(billing.status, SupporterStatus.verificationRejected);
    expect(billing.owned, isFalse);
    expect(store.acknowledgmentAttempts, 0);
  });

  test('verification and acknowledgment failures allow a safe restore retry',
      () async {
    await billing.refresh();
    store.purchases = [purchase(PurchaseStatus.purchased)];
    store.ownershipError = true;
    store.events.add(store.purchases);
    await flushEvents();
    expect(billing.status, SupporterStatus.verificationUnavailable);
    expect(billing.owned, isFalse);
    store.ownershipError = false;
    store.acknowledgmentError = true;
    await billing.refresh();
    expect(billing.status, SupporterStatus.verificationUnavailable);
    expect(billing.owned, isFalse);
    store.acknowledgmentError = false;
    await billing.refresh(manual: true);
    expect(billing.status, SupporterStatus.restored);
    expect(billing.owned, isTrue);
    expect(store.acknowledgmentAttempts, 2);
  });

  test('fresh ownership on preflight prevents a second purchase', () async {
    await billing.refresh();
    store.purchases = [purchase(PurchaseStatus.purchased)];
    await billing.buy();
    expect(store.launches, 0);
    expect(billing.status, SupporterStatus.alreadyOwned);
    expect(billing.owned, isTrue);
  });

  test(
      'restart restores ownership; network error retains it; empty Play query clears it',
      () async {
    await billing.refresh(manual: true);
    expect(billing.status, SupporterStatus.noPurchase);
    store.purchases = [
      purchase(PurchaseStatus.purchased, needsAcknowledgment: false)
    ];
    billing.dispose();
    billing = SupporterBilling(store);
    await billing.refresh();
    expect(billing.owned, isTrue);
    expect(store.acknowledgmentAttempts, 0);
    store.ownershipError = true;
    await billing.refresh(manual: true);
    expect(billing.status, SupporterStatus.restoreFailed);
    expect(billing.owned, isTrue);
    store.ownershipError = false;
    store.purchases = [];
    await billing.refresh();
    expect(billing.owned, isFalse);
    expect(billing.canBuy, isTrue);
  });

  test('a different Play account with a pending purchase loses the old badge',
      () async {
    store.purchases = [purchase(PurchaseStatus.purchased)];
    await billing.refresh();
    expect(billing.owned, isTrue);
    store.purchases = [
      purchase(PurchaseStatus.pending, token: 'different-account-token'),
    ];
    await billing.refresh(manual: true);
    expect(billing.owned, isFalse);
    expect(billing.status, SupporterStatus.pending);
    expect(billing.canBuy, isFalse);
  });

  test('library restore notification neither grants nor removes Play ownership',
      () async {
    await billing.refresh();
    LibraryBackup.revision.value++;
    expect(billing.owned, isFalse);
    store.purchases = [purchase(PurchaseStatus.purchased)];
    await billing.refresh();
    LibraryBackup.revision.value++;
    expect(billing.owned, isTrue);
  });

  testWidgets('Help opens support during a store outage and remains navigable',
      (tester) async {
    await mountSupport(tester, const LoanHelpScreen(),
        available: false, enable: false);
    final supportButton =
        find.widgetWithText(OutlinedButton, supportScreenTitle);
    expect(
        find.descendant(
            of: supportButton, matching: find.byIcon(Icons.favorite)),
        findsOneWidget);
    await tester.tap(supportButton);
    await tester.pumpAndSettle();
    await toggleTesting(tester);
    expect(find.text('Google Play jest teraz niedostępny.'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('Przyjaciel Biblioteki'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Kopia zapasowa'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'Polish checkout, pending and restore UI uses Play price and confirms ownership',
      (tester) async {
    final play = await mountSupport(tester, const SupportScreen());
    final button = buyButton('Kup odznakę — 2,49 €');
    const thanks = 'Dziękuję za wsparcie rozwoju Mojej Biblioteki! ❤️';
    expect(find.text(thanks), findsNothing);
    await tester.tap(button);
    await tester.pumpAndSettle();
    play.events.add([purchase(PurchaseStatus.canceled)]);
    await tester.pumpAndSettle();
    expect(find.text('Zakup został anulowany.'), findsOneWidget);
    expect(find.text(thanks), findsNothing);

    await tester.tap(button);
    await tester.pumpAndSettle();
    play.purchases = [purchase(PurchaseStatus.pending)];
    play.events.add(play.purchases);
    await tester.pumpAndSettle();
    expect(find.text('Płatność oczekuje na potwierdzenie w Google Play.'),
        findsOneWidget);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    expect(find.text(thanks), findsNothing);

    play.purchases = [purchase(PurchaseStatus.purchased)];
    final restore = find.text('Przywróć zakup');
    await tester.scrollUntilVisible(restore.hitTestable(), 100);
    await tester.tap(restore);
    await tester.pumpAndSettle();
    expect(find.text('Zakup został przywrócony.'), findsOneWidget);
    expect(find.text(thanks), findsOneWidget);
    expect(button, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('narrow Help header follows Play ownership and revocation',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final navigator = GlobalKey<NavigatorState>();
    final play = FakePlay();
    addTearDown(play.events.close);
    late SupporterBilling billing;
    await tester.pumpWidget(SupporterBillingScope.forApp(
      debug: true,
      testFlag: true,
      web: false,
      platform: TargetPlatform.android,
      createBilling: () => billing = SupporterBilling(play),
      child: MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
          ),
          child: child!,
        ),
        home: const LoanHelpScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text(supportScreenTitle));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(testSwitch.hitTestable(), 100);
    await toggleTesting(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();

    final badge = find.descendant(
      of: find.byType(AppBar),
      matching: find.byType(SupporterBadgeImage),
    );
    expect(badge, findsNothing);
    for (final status in [
      PurchaseStatus.pending,
      PurchaseStatus.canceled,
      PurchaseStatus.error,
    ]) {
      play.events.add([purchase(status)]);
      await tester.pumpAndSettle();
      expect(badge, findsNothing);
    }

    play.purchases = [purchase(PurchaseStatus.purchased)];
    play.events.add(play.purchases);
    await tester.pumpAndSettle();
    expect(badge, findsOneWidget);
    expect(tester.getTopRight(badge).dx,
        lessThan(tester.getTopLeft(find.text('Pomoc')).dx));
    expect(tester.takeException(), isNull);

    play.ownershipError = true;
    await billing.refresh();
    await tester.pumpAndSettle();
    expect(badge, findsOneWidget);

    play.ownershipError = false;
    play.purchases = [];
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(badge, findsNothing);

    await tester.tap(find.text(supportScreenTitle));
    await tester.pumpAndSettle();
    final restore = find.text('Przywróć zakup');
    await tester.scrollUntilVisible(restore.hitTestable(), 100);
    play.purchases = [
      purchase(PurchaseStatus.restored, needsAcknowledgment: false),
    ];
    await tester.tap(restore);
    await tester.pumpAndSettle();
    expect(find.text('Zakup został przywrócony.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(badge, findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('application resume recovers an update the stream missed',
      (tester) async {
    final play = await mountSupport(tester, const SupportScreen());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    play.purchases = [purchase(PurchaseStatus.purchased)];
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Przyjaciel Biblioteki'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
