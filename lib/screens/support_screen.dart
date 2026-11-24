import 'package:flutter/material.dart';

import '../services/support_browser.dart';
import 'supporter_badge.dart';

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
    final billing = SupporterBillingScope.read(context);
    return Scaffold(
      appBar: AppBar(title: const Text('O aplikacji')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Semantics(
              header: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    billing == null
                        ? Icons.coffee_outlined
                        : Icons.workspace_premium_outlined,
                    applyTextScaling: true,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Wesprzyj rozwój Mojej Biblioteki',
                      semanticsLabel: billing == null
                          ? '☕ Wesprzyj rozwój Mojej Biblioteki'
                          : null,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (billing != null) ...[
              const Text(
                  'Moja Biblioteka jest darmową aplikacją do katalogowania książek i zarządzania wypożyczeniami.'),
              const SizedBox(height: 16),
              SupporterBadge(billing: billing),
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
