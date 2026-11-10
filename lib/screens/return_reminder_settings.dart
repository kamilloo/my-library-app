import 'package:flutter/material.dart';

import '../data/library_repository.dart';
import '../models/book.dart';
import '../services/return_reminders.dart';

class ReturnReminderSettings extends StatefulWidget {
  const ReturnReminderSettings({
    required this.book,
    required this.repository,
    super.key,
  });
  final Book book;
  final LibraryRepository repository;

  @override
  State<ReturnReminderSettings> createState() => _ReturnReminderSettingsState();
}

class _ReturnReminderSettingsState extends State<ReturnReminderSettings> {
  bool enabled = false;
  bool busy = true;
  String? message;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final value = await widget.repository.reminders!.enabled(widget.book.id);
      if (mounted) {
        setState(() {
          enabled = value;
          busy = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          message = 'Nie udało się wczytać ustawień przypomnienia.';
        });
      }
    }
  }

  Future<void> toggle(bool value) async {
    if (busy) return;
    setState(() => busy = true);
    if (value) {
      try {
        if (await widget.repository.reminders!.notifications.needsRationale()) {
          if (!mounted) return;
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Powiadomienia o zwrocie'),
              content: const Text(
                  'Zgoda pozwala wyświetlić lokalne przypomnienie w dniu zwrotu. Możesz odmówić i nadal zapisać wypożyczenie.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Anuluj')),
                TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Kontynuuj')),
              ],
            ),
          );
          if (confirmed != true) {
            if (mounted) setState(() => busy = false);
            return;
          }
        }
      } catch (_) {
        if (!mounted) return;
        setState(() {
          busy = false;
          message = 'Nie udało się sprawdzić uprawnień. Spróbuj ponownie.';
        });
        return;
      }
    }
    if (!mounted) return;
    setState(() => busy = true);
    final result =
        await widget.repository.reminders!.setEnabled(widget.book.id, value);
    var savedEnabled = enabled;
    try {
      savedEnabled = await widget.repository.reminders!.enabled(widget.book.id);
    } catch (_) {
      // Keep the previous switch state if storage is unavailable.
    }
    if (!mounted) return;
    setState(() {
      busy = false;
      enabled = savedEnabled;
      message = switch (result) {
        ReminderResult.enabled =>
          'Przypomnienie włączone. Planowane o 09:00 w dniu zwrotu. Przy ponad 60 terminach najbliższe mają pierwszeństwo.',
        ReminderResult.disabled => 'Przypomnienie wyłączone.',
        ReminderResult.denied =>
          'Brak zgody na powiadomienia. Włącz powiadomienia i kanał „Terminy zwrotu” w ustawieniach systemu, a potem spróbuj ponownie.',
        ReminderResult.ineligible =>
          'Podaj osobę wypożyczającą i przyszły termin zwrotu. Godzina 09:00 musi być w przyszłości.',
        ReminderResult.failed =>
          'Nie udało się ustawić przypomnienia. Spróbuj ponownie. Dane wypożyczenia są zapisane.',
      };
    });
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Przypomnij o zwrocie'),
            subtitle: const Text(
                'Lokalne powiadomienie o 09:00 w dniu zwrotu. Może pojawić się z opóźnieniem. Bez konta i synchronizacji.'),
            value: enabled,
            onChanged: busy ? null : toggle,
          ),
          if (busy) const LinearProgressIndicator(),
          if (message != null) Text(message!),
          TextButton(
            onPressed: busy
                ? null
                : () async {
                    try {
                      await widget.repository.reminders!.notifications
                          .openSettings();
                    } catch (_) {
                      if (mounted) {
                        setState(() => message =
                            'Otwórz ustawienia powiadomień aplikacji w ustawieniach systemu.');
                      }
                    }
                  },
            child: const Text('Ustawienia powiadomień'),
          ),
        ],
      );
}
