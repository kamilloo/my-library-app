import 'package:flutter/material.dart';

import '../data/library_repository.dart';
import '../models/book.dart';

class BookHistorySection extends StatefulWidget {
  const BookHistorySection({
    required this.repository,
    required this.bookId,
    super.key,
  });

  final LibraryRepository repository;
  final String bookId;

  @override
  State<BookHistorySection> createState() => _BookHistorySectionState();
}

class _BookHistorySectionState extends State<BookHistorySection> {
  late Future<List<HistoryEntry>> history = _load();

  Future<List<HistoryEntry>> _load() =>
      widget.repository.historyForBook(widget.bookId);

  @override
  void didUpdateWidget(covariant BookHistorySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookId != widget.bookId ||
        oldWidget.repository != widget.repository) {
      history = _load();
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Historia książki',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          FutureBuilder<List<HistoryEntry>>(
            future: history,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const LinearProgressIndicator();
              }
              if (snapshot.hasError) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Nie udało się wczytać historii książki.'),
                    TextButton(
                      onPressed: () => setState(() => history = _load()),
                      child: const Text('Spróbuj ponownie'),
                    ),
                  ],
                );
              }
              final entries = snapshot.data ?? const <HistoryEntry>[];
              if (entries.isEmpty) {
                return const Text(
                    'Brak zapisanych zdarzeń dla tej książki. Wypożyczenia i zwroty pojawią się tutaj.');
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Ostatnie 50 zdarzeń · od najnowszych'),
                  for (final entry in entries)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_actionLabel(entry.action)),
                      subtitle: Text([
                        if (entry.detail?.trim().isNotEmpty ?? false)
                          entry.detail!,
                        _dateTime(entry.timestamp.toLocal()),
                      ].join('\n')),
                    ),
                ],
              );
            },
          ),
        ],
      );
}

String _actionLabel(String action) => switch (action) {
      'added' => 'Dodano na półkę',
      'borrowed' => 'Wypożyczono',
      'returned' => 'Zwrócono',
      'given' => 'Oddano na stałe',
      'return_date_changed' => 'Zmieniono termin zwrotu',
      _ => 'Zmieniono książkę',
    };

String _dateTime(DateTime date) {
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${pad(date.day)}.${pad(date.month)}.${date.year} · ${pad(date.hour)}:${pad(date.minute)}';
}
