import 'dart:async';

import 'package:flutter/material.dart';

import '../services/supporter_billing.dart';

class SupporterBillingScope extends StatefulWidget {
  const SupporterBillingScope({
    super.key,
    required this.billing,
    required this.child,
  });

  final SupporterBilling billing;
  final Widget child;

  static SupporterBilling? read(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_BillingProvider>()?.billing;

  @override
  State<SupporterBillingScope> createState() => _SupporterBillingScopeState();
}

class _SupporterBillingScopeState extends State<SupporterBillingScope>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(widget.billing.refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(widget.billing.refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.billing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _BillingProvider(billing: widget.billing, child: widget.child);
}

class _BillingProvider extends InheritedWidget {
  const _BillingProvider({required this.billing, required super.child});

  final SupporterBilling billing;

  @override
  bool updateShouldNotify(_BillingProvider oldWidget) =>
      billing != oldWidget.billing;
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
              const Text(
                'Jeśli chcesz wesprzeć jej dalszy rozwój, możesz kupić symboliczną odznakę Przyjaciel Biblioteki.\n\n'
                'Zakup jest jednorazowy i nie odblokowuje dodatkowych funkcji.',
              ),
              const SizedBox(height: 16),
              if (billing.owned)
                Semantics(
                  container: true,
                  child: Card(
                    color: theme.colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Icon(Icons.workspace_premium,
                              size: 40,
                              color: theme.colorScheme.onPrimaryContainer),
                          const SizedBox(height: 8),
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
              else
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed:
                      billing.canBuy ? () => unawaited(billing.buy()) : null,
                  icon: const Icon(Icons.workspace_premium_outlined),
                  label: Text(
                      price == null ? 'Kup odznakę' : 'Kup odznakę — $price'),
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
