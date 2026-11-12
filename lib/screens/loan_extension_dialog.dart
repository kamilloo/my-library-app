import 'package:flutter/material.dart';

import '../data/library_repository.dart';
import '../models/book.dart';
import '../models/return_date.dart';

class LoanExtensionDialog extends StatefulWidget {
  const LoanExtensionDialog(
      {required this.book,
      required this.repository,
      this.requestLoanId,
      super.key});
  final Book book;
  final String? requestLoanId;
  final LibraryRepository repository;

  @override
  State<LoanExtensionDialog> createState() => _LoanExtensionDialogState();
}

class _LoanExtensionDialogState extends State<LoanExtensionDialog> {
  DateTime? proposed;
  int? preset;
  bool saving = false;
  String? error;

  String? get validation => loanExtensionValidation(
      widget.book.returnDate, proposed, widget.repository.currentTime);

  Future<void> chooseDate() async {
    final today = calendarDate(widget.repository.currentTime);
    final tomorrow = extendedReturnDate(today, 1);
    final old = widget.book.returnDate;
    final afterOld = old == null ? tomorrow : extendedReturnDate(old, 1);
    final first = afterOld.isAfter(tomorrow) ? afterOld : tomorrow;
    final horizon = DateTime(today.year + 10, 12, 31);
    final chosen = await showDatePicker(
      context: context,
      currentDate: today,
      initialDate:
          proposed != null && !proposed!.isBefore(first) ? proposed : first,
      firstDate: first,
      lastDate: first.isAfter(horizon) ? first : horizon,
      helpText: 'Nowy termin zwrotu',
      cancelText: 'Anuluj',
      confirmText: 'Wybierz',
      errorInvalidText: 'Wybierz przyszłą datę późniejszą niż obecny termin.',
      errorFormatText: 'Wpisz poprawną datę.',
    );
    if (chosen != null && mounted) {
      setState(() {
        proposed = chosen;
        preset = null;
        error = null;
      });
    }
  }

  Future<void> confirm() async {
    if (saving || validation != null) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final Object updated = widget.requestLoanId == null
          ? await widget.repository.extendLoan(widget.book.id, proposed!)
          : await widget.repository
              .prepareExtension(widget.requestLoanId!, proposed!);
      if (mounted) Navigator.pop(context, updated);
    } on FormatException catch (exception) {
      if (mounted) setState(() => error = exception.message);
    } on ReturnDateException catch (exception) {
      if (mounted) setState(() => error = exception.message);
    } catch (_) {
      if (mounted) {
        setState(() =>
            error = 'Nie udało się przedłużyć wypożyczenia. Spróbuj ponownie.');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.requestLoanId == null
            ? 'Przedłuż wypożyczenie'
            : 'Poproś o przedłużenie'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.requestLoanId != null)
                const Text(
                    'Prośba nie przedłuża wypożyczenia. Termin zmieni się dopiero po jawnym zaimportowaniu zatwierdzonego potwierdzenia.'),
              Text(widget.book.returnDate == null
                  ? 'Nie ustawiono terminu zwrotu'
                  : 'Obecny termin: ${formatReturnDate(widget.book.returnDate!)}'),
              if (widget.book.returnDate == null)
                const Text(
                    'Wybierz nowy termin. Bez obecnej daty nie można obliczyć prolongaty.'),
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: [
                for (final days in [7, 14, 30])
                  ChoiceChip(
                    label: Text('+$days dni'),
                    selected: preset == days,
                    onSelected: saving || widget.book.returnDate == null
                        ? null
                        : (_) {
                            setState(() {
                              preset = days;
                              proposed = extendedReturnDate(
                                  widget.book.returnDate!, days);
                              error = null;
                            });
                          },
                  ),
              ]),
              TextButton(
                  onPressed: saving ? null : chooseDate,
                  child: const Text('Wybierz datę')),
              if (proposed != null)
                Text('Nowy termin zwrotu: ${formatReturnDate(proposed!)}'),
              if (proposed != null && validation != null) Text(validation!),
              if (error != null) Text(error!),
              if (saving) const LinearProgressIndicator(),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: saving ? null : () => Navigator.pop(context),
              child: const Text('Anuluj')),
          FilledButton(
            onPressed: saving || validation != null ? null : confirm,
            child: Text(widget.requestLoanId == null
                ? 'Potwierdź prolongatę'
                : 'Przygotuj prośbę SMS'),
          ),
        ],
      );
}
