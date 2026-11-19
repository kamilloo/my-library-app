import 'package:flutter/material.dart';

import '../data/library_repository.dart';
import '../models/book.dart';

class BookHistorySection extends StatefulWidget {
  const BookHistorySection({
    required this.repository,
    required this.bookId,
    required this.revision,
    super.key,
  });

  final LibraryRepository repository;
  final String bookId;
  final (DateTime, int) revision;

  @override
  State<BookHistorySection> createState() => _BookHistorySectionState();
}

class _BookHistorySectionState extends State<BookHistorySection>
    with AutomaticKeepAliveClientMixin {
  final _entries = <HistoryEntry>[];
  bool _hasMore = false;
  bool _loading = false;
  bool _failed = false;
  int _generation = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  @override
  void didUpdateWidget(covariant BookHistorySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookId != widget.bookId ||
        oldWidget.repository != widget.repository ||
        oldWidget.revision != widget.revision) {
      _generation++;
      _entries.clear();
      _hasMore = false;
      _loading = false;
      _loadPage();
    }
  }

  Future<void> _loadPage() async {
    if (_loading) return;
    final generation = _generation;
    final pageSize = _entries.isEmpty ? 5 : 10;
    final beforeId = _entries.lastOrNull?.id;
    setState(() {
      _loading = true;
      _failed = false;
    });

    try {
      // The extra row tells us whether to offer another page.
      final page = await widget.repository.historyForBook(
        widget.bookId,
        limit: pageSize + 1,
        beforeId: beforeId,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _entries.addAll(page.take(pageSize));
        _hasMore = page.length > pageSize;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Historia książki', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (_entries.isNotEmpty) ...[
          const Text('Zdarzenia od najnowszych'),
          for (final entry in _entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_actionLabel(entry.action)),
              subtitle: Text([
                if (entry.detail?.trim().isNotEmpty ?? false) entry.detail!,
                _dateTime(entry.timestamp.toLocal()),
              ].join('\n')),
            ),
        ],
        if (_loading)
          const LinearProgressIndicator()
        else if (_failed) ...[
          const Text('Nie udało się wczytać historii książki.'),
          TextButton(
            onPressed: _loadPage,
            child: const Text('Spróbuj ponownie'),
          ),
        ] else if (_entries.isEmpty)
          const Text(
              'Brak zapisanych zdarzeń dla tej książki. Wypożyczenia i zwroty pojawią się tutaj.')
        else if (_hasMore)
          TextButton(
            onPressed: _loadPage,
            child: const Text('Pokaż więcej'),
          ),
      ],
    );
  }
}

String _actionLabel(String action) => switch (action) {
      'added' => 'Dodano na półkę',
      'borrowed' => 'Wypożyczono',
      'returned' => 'Zwrócono',
      'given' => 'Oddano na stałe',
      'return_date_changed' => 'Zmieniono termin zwrotu',
      'loan_extended' => 'Przedłużono wypożyczenie',
      _ => 'Zmieniono książkę',
    };

String _dateTime(DateTime date) {
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${pad(date.day)}.${pad(date.month)}.${date.year} · ${pad(date.hour)}:${pad(date.minute)}';
}
