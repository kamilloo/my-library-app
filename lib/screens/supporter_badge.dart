import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/supporter_billing.dart';

class SupporterBillingScope extends StatefulWidget {
  const SupporterBillingScope._({
    required this.createBilling,
    required this.canSimulate,
    required this.child,
  });

  final SupporterBilling Function()? createBilling;
  final bool canSimulate;
  final Widget child;

  static Widget forApp({
    required SupporterBilling Function() createBilling,
    required Widget child,
    bool debug = kDebugMode,
    bool testFlag = const bool.fromEnvironment('PLAY_SUPPORTER_BILLING_TEST'),
    bool licenseTestFlag =
        const bool.fromEnvironment('PLAY_SUPPORTER_LICENSE_TEST'),
    bool web = kIsWeb,
    TargetPlatform? platform,
  }) {
    final target = platform ?? defaultTargetPlatform;
    final canSimulate = isSupporterBillingEnabled(
        debug: debug, testFlag: testFlag, web: web, platform: target);
    final canTestBilling = isSupporterBillingEnabled(
        debug: debug, testFlag: licenseTestFlag, web: web, platform: target);
    if (!canSimulate && !canTestBilling) return child;
    return SupporterBillingScope._(
      createBilling: canTestBilling ? createBilling : null,
      canSimulate: canSimulate,
      child: child,
    );
  }

  static SupporterBillingProvider? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SupporterBillingProvider>();

  @override
  State<SupporterBillingScope> createState() => _SupporterBillingScopeState();
}

class _SupporterBillingScopeState extends State<SupporterBillingScope>
    with WidgetsBindingObserver {
  SupporterBilling? _billing;
  bool _simulatedSupporterOwned = false;

  void _setSimulatedSupporterOwned(bool enabled) {
    if (!widget.canSimulate || enabled == _simulatedSupporterOwned) return;
    setState(() => _simulatedSupporterOwned = enabled);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _setEnabled(bool enabled) {
    final createBilling = widget.createBilling;
    if (createBilling == null || _simulatedSupporterOwned) return;
    final billing = _billing;
    if (enabled == (billing != null)) return;
    if (billing != null && !billing.canStop) return;

    final next = enabled ? createBilling() : null;
    billing?.dispose();
    setState(() => _billing = next);
    if (next != null) unawaited(next.refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final billing = _billing;
    if (state == AppLifecycleState.resumed &&
        billing != null &&
        !_simulatedSupporterOwned) {
      unawaited(billing.refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _billing?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SupporterBillingProvider._(
        notifier: _billing,
        setEnabled: widget.createBilling == null ? null : _setEnabled,
        simulatedSupporterOwned: _simulatedSupporterOwned,
        setSimulatedSupporterOwned:
            widget.canSimulate ? _setSimulatedSupporterOwned : null,
        child: widget.child,
      );
}

class SupporterBillingProvider extends InheritedNotifier<SupporterBilling> {
  const SupporterBillingProvider._({
    required super.notifier,
    required this.setEnabled,
    required this.simulatedSupporterOwned,
    required this.setSimulatedSupporterOwned,
    required super.child,
  });

  final ValueChanged<bool>? setEnabled;
  final bool simulatedSupporterOwned;
  final ValueChanged<bool>? setSimulatedSupporterOwned;

  SupporterBilling? get billing => notifier;
  bool get owned => simulatedSupporterOwned || billing?.owned == true;

  @override
  bool updateShouldNotify(SupporterBillingProvider oldWidget) =>
      super.updateShouldNotify(oldWidget) ||
      simulatedSupporterOwned != oldWidget.simulatedSupporterOwned ||
      setEnabled != oldWidget.setEnabled ||
      setSimulatedSupporterOwned != oldWidget.setSimulatedSupporterOwned;
}

class SupporterBadgeImage extends StatelessWidget {
  const SupporterBadgeImage({super.key, required this.size});

  static const asset = 'assets/supporter/przyjaciel_biblioteki.png';

  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        semanticLabel: 'Przyjaciel Biblioteki — odznaka wspierającego',
      );
}

class SupporterThankYou extends StatelessWidget {
  const SupporterThankYou({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      child: Card(
        color: theme.colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text('Przyjaciel Biblioteki',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
              const SizedBox(height: 8),
              Text('Dziękuję za wsparcie rozwoju Mojej Biblioteki! ❤️',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: theme.colorScheme.onPrimaryContainer)),
            ],
          ),
        ),
      ),
    );
  }
}

class SupporterBadge extends StatelessWidget {
  const SupporterBadge({super.key, required this.billing});

  final SupporterBilling billing;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: billing,
        builder: (context, _) {
          final message = _message(billing.status);
          final price = billing.product?.price;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (billing.owned)
                const SupporterThankYou()
              else if (price != null)
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed:
                      billing.canBuy ? () => unawaited(billing.buy()) : null,
                  child: Text('Kup odznakę — $price'),
                ),
              const SizedBox(height: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: billing.canRestore
                    ? () => unawaited(billing.refresh(manual: true))
                    : null,
                child: const Text('Przywróć zakup'),
              ),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Semantics(liveRegion: true, child: Text(message)),
                ),
            ],
          );
        },
      );

  String? _message(SupporterStatus status) => switch (status) {
        SupporterStatus.initializing => 'Łączenie z Google Play…',
        SupporterStatus.storeUnavailable =>
          'Google Play jest teraz niedostępny.',
        SupporterStatus.productUnavailable =>
          'Odznaka jest teraz niedostępna w Google Play.',
        SupporterStatus.available || SupporterStatus.owned => null,
        SupporterStatus.checkout => 'Dokończ zakup w Google Play.',
        SupporterStatus.pending =>
          'Płatność oczekuje na potwierdzenie w Google Play.',
        SupporterStatus.verifying => 'Trwa potwierdzanie zakupu…',
        SupporterStatus.canceled => 'Zakup został anulowany.',
        SupporterStatus.purchaseFailed =>
          'Zakup nie powiódł się. Spróbuj ponownie.',
        SupporterStatus.alreadyOwned =>
          'Masz już tę odznakę na koncie Google Play.',
        SupporterStatus.restoring => 'Trwa przywracanie zakupu…',
        SupporterStatus.restored => 'Zakup został przywrócony.',
        SupporterStatus.noPurchase =>
          'Nie znaleziono zakupu na tym koncie Google Play.',
        SupporterStatus.verificationUnavailable =>
          'Nie można teraz potwierdzić zakupu. Spróbuj przywrócić zakup później.',
        SupporterStatus.verificationRejected =>
          'Google Play nie potwierdził zakupu. Spróbuj przywrócić zakup.',
        SupporterStatus.restoreFailed =>
          'Nie można teraz przywrócić zakupu. Spróbuj ponownie później.',
      };
}
