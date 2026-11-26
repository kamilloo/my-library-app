import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/support_browser.dart';
import 'supporter_badge.dart';

const supportScreenTitle = 'Wesprzyj Moją Bibliotekę';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key, this.loadAction = loadSupportAction});

  final Future<VoidCallback?> Function() loadAction;

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  late final _action = widget.loadAction();

  @override
  Widget build(BuildContext context) {
    final developerMode = SupporterBillingScope.of(context);
    final billing = developerMode?.billing;
    final simulated = developerMode?.simulatedSupporterOwned ?? false;
    final isAndroid = developerMode != null ||
        (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);
    return Scaffold(
      appBar: AppBar(title: const Text(supportScreenTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Semantics(
              header: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isAndroid) ...[
                    const Icon(Icons.coffee_outlined, applyTextScaling: true),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      'Wesprzyj rozwój Mojej Biblioteki',
                      semanticsLabel: !isAndroid
                          ? '☕ Wesprzyj rozwój Mojej Biblioteki'
                          : null,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (isAndroid) ...[
              const Center(child: SupporterBadgeImage(size: 144)),
              const SizedBox(height: 16),
              if (simulated) ...[
                const SupporterThankYou(),
                const Text('Symulacja zakupu — tylko do testów'),
              ] else
                const Text(
                  'Wesprzyj rozwój Mojej Biblioteki, kupując jednorazową odznakę Przyjaciel Biblioteki.\n\n'
                  'Zakup jest dobrowolny. Wszystkie funkcje aplikacji pozostają bezpłatne.',
                ),
              const SizedBox(height: 16),
              if (developerMode != null) ...[
                Semantics(
                  header: true,
                  child: Text(
                    'Tryb deweloperski',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (developerMode.setSimulatedSupporterOwned != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Symuluj zakup odznaki'),
                    subtitle: const Text(
                      'Włącz, aby zobaczyć odznakę Przyjaciel Biblioteki tak, jak po udanym zakupie. Nie jest wykonywana żadna płatność.',
                    ),
                    value: simulated,
                    onChanged: developerMode.setSimulatedSupporterOwned,
                  ),
                if (developerMode.setEnabled != null && !simulated)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Testowanie zakupów Google Play'),
                    subtitle: const Text(
                      'Włącz testowanie zakupu odznaki Przyjaciel Biblioteki przy użyciu konta testera Google Play.',
                    ),
                    value: billing != null,
                    onChanged: billing == null || billing.canStop
                        ? developerMode.setEnabled
                        : null,
                  ),
              ],
              if (!simulated && billing != null)
                SupporterBadge(billing: billing)
              else if (!simulated)
                const Text(
                    'Zakup odznaki jest niedostępny w tej wersji aplikacji.'),
            ] else ...[
              const Text(
                'Moja Biblioteka jest darmową aplikacją do katalogowania książek i zarządzania wypożyczeniami.\n\n'
                'Jeśli aplikacja jest dla Ciebie przydatna, możesz dobrowolnie wesprzeć jej dalszy rozwój.\n\n'
                'Wsparcie jest całkowicie opcjonalne i nie wiąże się z żadnymi dodatkowymi korzyściami. Wszystkie funkcje aplikacji pozostają bezpłatne.',
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.favorite,
                      size: 16,
                      applyTextScaling: true,
                      color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Dziękuję za każde wsparcie!',
                      semanticsLabel: '❤️ Dziękuję za każde wsparcie!',
                    ),
                  ),
                ],
              ),
              FutureBuilder<VoidCallback?>(
                future: _action,
                builder: (context, snapshot) {
                  final action = snapshot.data;
                  if (action == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: action,
                      icon: const Icon(Icons.coffee_outlined),
                      label: const Text(
                        'Wesprzyj projekt',
                        semanticsLabel: '☕ Wesprzyj projekt',
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
