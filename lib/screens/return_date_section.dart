import 'package:flutter/material.dart';

import '../data/library_repository.dart';
import '../models/book.dart';
import '../models/return_date.dart';
import 'loan_extension_dialog.dart';

class ReturnDateSection extends StatefulWidget {
  const ReturnDateSection({
    required this.book,
    required this.repository,
    required this.onBookChanged,
    super.key,
  });
  final Book book;
  final LibraryRepository repository;
  final ValueChanged<Book> onBookChanged;

  @override
  State<ReturnDateSection> createState() => _ReturnDateSectionState();
}

class _ReturnDateSectionState extends State<ReturnDateSection> {
  bool saving = false;
  String? error;

  Future<void> save(DateTime? date) async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final updated =
          await widget.repository.updateReturnDate(widget.book.id, date);
      if (mounted) widget.onBookChanged(updated);
    } on ReturnDateException catch (exception) {
      if (mounted) setState(() => error = exception.message);
    } catch (_) {
      if (mounted) {
        setState(() =>
            error = 'Nie udało się zmienić terminu zwrotu. Spróbuj ponownie.');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> chooseDate() async {
    final today = calendarDate(widget.repository.currentTime);
    final saved = widget.book.returnDate == null
        ? null
        : calendarDate(widget.book.returnDate!);
    final horizon = DateTime(today.year + 10, 12, 31);
    final selected = await showDatePicker(
      context: context,
      currentDate: today,
      initialDate: saved ?? today,
      firstDate: saved != null && saved.isBefore(today) ? saved : today,
      lastDate: saved != null && saved.isAfter(horizon) ? saved : horizon,
      // An overdue saved date remains selectable as an unchanged value.
      selectableDayPredicate: (date) => !date.isBefore(today) || date == saved,
      helpText: 'Zmień termin zwrotu',
      cancelText: 'Anuluj',
      confirmText: 'Zapisz',
      errorInvalidText: 'Termin zwrotu nie może być w przeszłości.',
      errorFormatText: 'Wpisz poprawną datę.',
    );
    if (selected != null && mounted) await save(selected);
  }

  Future<void> extend() async {
    final updated = await showDialog<Book>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          LoanExtensionDialog(book: widget.book, repository: widget.repository),
    );
    if (updated == null || !mounted) return;
    widget.onBookChanged(updated);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          'Przedłużono wypożyczenie do ${formatReturnDate(updated.returnDate!)}.'),
    ));
  }

  Future<void> clearDate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Usunąć termin zwrotu?'),
        content: const Text(
            'Książka pozostanie wypożyczona tej samej osobie. Przypomnienie o tym terminie zostanie anulowane.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Anuluj')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Usuń termin')),
        ],
      ),
    );
    if (confirmed == true && mounted) await save(null);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.book.status != BookStatus.borrowed) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Wypożyczono: ${widget.book.borrowedBy ?? 'Nie podano osoby'}'),
        Text(widget.book.borrowedDate == null
            ? 'Nie ustawiono daty wypożyczenia'
            : 'Data wypożyczenia: ${formatReturnDate(widget.book.borrowedDate!)}'),
        Text(
            widget.book.returnDate == null
                ? 'Nie ustawiono terminu zwrotu'
                : 'Termin zwrotu: ${formatReturnDate(widget.book.returnDate!)}',
            style: Theme.of(context).textTheme.titleMedium),
        Wrap(spacing: 8, children: [
          TextButton(
              onPressed: saving ? null : chooseDate,
              child: const Text('Zmień termin zwrotu')),
          TextButton(
              onPressed: saving ? null : extend,
              child: const Text('Przedłuż wypożyczenie')),
          if (widget.book.returnDate != null)
            TextButton(
                onPressed: saving ? null : clearDate,
                child: const Text('Usuń termin zwrotu')),
        ]),
        if (saving) const LinearProgressIndicator(),
        if (error != null) Text(error!),
      ],
    );
  }
}
