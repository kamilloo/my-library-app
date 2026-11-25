import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/supporter_billing.dart';

class SupporterBillingScope extends StatefulWidget {
  const SupporterBillingScope._({
    required this.createBilling,
    required this.child,
  });

  final SupporterBilling Function() createBilling;
  final Widget child;

  static Widget forApp({
    required SupporterBilling Function() createBilling,
    required Widget child,
    bool debug = kDebugMode,
    bool testFlag = const bool.fromEnvironment('PLAY_SUPPORTER_BILLING_TEST'),
    bool web = kIsWeb,
    TargetPlatform? platform,
  }) =>
      isSupporterBillingEnabled(
        debug: debug,
        testFlag: testFlag,
        web: web,
        platform: platform ?? defaultTargetPlatform,
      )
          ? SupporterBillingScope._(createBilling: createBilling, child: child)
          : child;

  static ({SupporterBilling? billing, ValueChanged<bool> setEnabled})? of(
    BuildContext context,
  ) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<_BillingProvider>();
    if (provider == null) return null;
    return (billing: provider.notifier, setEnabled: provider.setEnabled);
  }

  @override
  State<SupporterBillingScope> createState() => _SupporterBillingScopeState();
}

class _SupporterBillingScopeState extends State<SupporterBillingScope>
    with WidgetsBindingObserver {
  SupporterBilling? _billing;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _setEnabled(bool enabled) {
    final billing = _billing;
    if (enabled == (billing != null)) return;
    if (billing != null && !billing.canStop) return;

    final next = enabled ? widget.createBilling() : null;
    billing?.dispose();
    setState(() => _billing = next);
    if (next != null) unawaited(next.refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final billing = _billing;
    if (state == AppLifecycleState.resumed && billing != null) {
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
  Widget build(BuildContext context) => _BillingProvider(
        notifier: _billing,
        setEnabled: _setEnabled,
        child: widget.child,
      );
}

class _BillingProvider extends InheritedNotifier<SupporterBilling> {
  const _BillingProvider({
    required super.notifier,
    required this.setEnabled,
    required super.child,
  });

  final ValueChanged<bool> setEnabled;
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

class SupporterBadge extends StatelessWidget {
  const SupporterBadge({super.key, required this.billing});

  final SupporterBilling billing;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: billing,
        builder: (context, _) {
          final theme = Theme.of(context);
          final message = _message(billing.status);
          final price = billing.product?.price;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (billing.owned)
                Semantics(
                  container: true,
                  child: Card(
                    color: theme.colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Text('Przyjaciel Biblioteki',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleLarge?.copyWith(
                                  color: theme.colorScheme.onPrimaryContainer)),
                          const SizedBox(height: 8),
                          Text(
                              'Dziękuję za wsparcie rozwoju Mojej Biblioteki! ❤️',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: theme.colorScheme.onPrimaryContainer)),
                        ],
                      ),
                    ),
                  ),
                )
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
