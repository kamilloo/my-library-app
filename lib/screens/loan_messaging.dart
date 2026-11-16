import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/library_repository.dart';
import '../models/loan_transfer.dart';
import '../models/loan_message.dart';
import '../models/return_date.dart';
import '../services/loan_sms.dart';
import '../models/readable_loan.dart';

String messageState(String state) => switch (state) {
      'prepared' => 'Przygotowana',
      'pending' => 'Oczekuje na odpowiedź (dostarczenie niezweryfikowane)',
      'approved' => 'Zatwierdzona',
      'rejected' => 'Odrzucona',
      'imported' => 'Potwierdzenie zaimportowane',
      _ => 'Nieznany stan',
    };

class SmsMessageScreen extends StatefulWidget {
  const SmsMessageScreen(
      {required this.text,
      this.initialPhone = '',
      this.onSavePhone,
      this.onSent,
      this.sms = const LoanSms(),
      super.key});
  final String text, initialPhone;
  final Future<void> Function(String)? onSavePhone;
  final Future<void> Function()? onSent;
  final LoanSms sms;
  @override
  State<SmsMessageScreen> createState() => _SmsMessageScreenState();
}

class _SmsMessageScreenState extends State<SmsMessageScreen> {
  late final phone = TextEditingController(text: widget.initialPhone);
  String? feedback;
  bool busy = false;
  @override
  void dispose() {
    phone.dispose();
    super.dispose();
  }

  Future<void> perform(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(
            () => feedback = 'Operacja nie powiodła się. Spróbuj ponownie.');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Przygotowana wiadomość')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            maxLength: 40,
            decoration:
                const InputDecoration(labelText: 'Opcjonalny numer odbiorcy')),
        if (widget.onSavePhone != null)
          OutlinedButton(
              onPressed: busy
                  ? null
                  : () => perform(() async {
                        await widget.onSavePhone!(phone.text);
                        if (mounted) {
                          setState(() => feedback =
                              'Zapisano lokalnie. Pusty numer usuwa zapisany kontakt.');
                        }
                      }),
              child: const Text('Zapisz numer tylko na tym urządzeniu')),
        SelectableText(widget.text),
        FilledButton(
            onPressed: busy
                ? null
                : () => perform(() async {
                      final opened =
                          await widget.sms.compose(widget.text, phone.text);
                      if (mounted) {
                        setState(() => feedback = opened
                            ? 'Otwarto aplikację SMS. Wysłanie i dostarczenie nie są potwierdzone.'
                            : 'Nie udało się otworzyć aplikacji SMS. Użyj kopiowania lub udostępniania.');
                      }
                    }),
            child: const Text('Otwórz aplikację SMS')),
        OutlinedButton(
            onPressed: busy
                ? null
                : () => perform(() async {
                      await Clipboard.setData(ClipboardData(text: widget.text));
                      if (mounted) {
                        setState(() => feedback = 'Skopiowano wiadomość.');
                      }
                    }),
            child: const Text('Kopiuj wiadomość')),
        OutlinedButton(
            onPressed: busy
                ? null
                : () => perform(() async {
                      final opened = await widget.sms.share(widget.text);
                      if (mounted) {
                        setState(() => feedback = opened
                            ? 'Otwarto udostępnianie. Dostarczenie nie jest potwierdzone.'
                            : 'Udostępnianie niedostępne. Użyj kopiowania.');
                      }
                    }),
            child: const Text('Udostępnij wiadomość')),
        if (widget.onSent != null)
          TextButton(
              onPressed: busy
                  ? null
                  : () => perform(() async {
                        final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (c) => AlertDialog(
                                    title: const Text(
                                        'Zapisać oczekiwanie na odpowiedź?'),
                                    content: const Text(
                                        'Potwierdzasz ręcznie, że wysłano prośbę. Aplikacja nie może sprawdzić jej dostarczenia.'),
                                    actions: [
                                      TextButton(
                                          onPressed: () => Navigator.pop(c),
                                          child: const Text('Anuluj')),
                                      FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(c, true),
                                          child: const Text(
                                              'Tak, wysłałem prośbę'))
                                    ]));
                        if (confirmed == true) {
                          await widget.onSent!();
                          if (mounted) {
                            setState(() => feedback =
                                'Oczekuje na odpowiedź. Dostarczenie niezweryfikowane.');
                          }
                        }
                      }),
              child: const Text('Zapisz, że wysłano prośbę')),
        if (feedback != null) Text(feedback!),
      ]));
}

class LoanMessagingScreen extends StatefulWidget {
  const LoanMessagingScreen(
      {required this.repository,
      required this.loan,
      required this.ownerSide,
      super.key});
  final LibraryRepository repository;
  final LoanTransfer loan;
  final bool ownerSide;
  @override
  State<LoanMessagingScreen> createState() => _LoanMessagingScreenState();
}

class _LoanMessagingScreenState extends State<LoanMessagingScreen> {
  late LoanTransfer loan = widget.loan;
  bool busy = false;
  String? error;
  late final history = widget.loan.origin == 'qr'
      ? widget.repository.messages(widget.ownerSide ? 'owner' : 'borrower',
          loanId: widget.loan.loanId)
      : Future.value(<Map<String, Object?>>[]);
  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => error = e is FormatException
            ? e.message
            : e is ReturnDateException
                ? e.message
                : 'Nie udało się wykonać operacji.');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> compose(String text) async {
    final role = widget.ownerSide
        ? 'owner'
        : loan.origin == 'qr'
            ? 'borrower'
            : 'borrower_${loan.origin}';
    final phone = await widget.repository.contact(role, loan.loanId);
    if (!mounted) return;
    await Navigator.push<void>(
        context,
        MaterialPageRoute(
            builder: (_) => SmsMessageScreen(
                text: text,
                initialPhone: phone ?? '',
                onSavePhone: (value) =>
                    widget.repository.saveContact(role, loan.loanId, value))));
  }

  Future<DateTime?> pick(String label) => showDatePicker(
      context: context,
      locale: const Locale('pl'),
      helpText: label,
      initialDate:
          loan.returnDate ?? calendarDate(widget.repository.currentTime),
      firstDate: DateTime(1900),
      lastDate: DateTime(2200, 12, 31));

  Future<void> request() async {
    final date = await pick('Proponowany termin zwrotu');
    if (date == null) return;
    final validation = loanExtensionValidation(
        loan.returnDate, date, widget.repository.currentTime);
    if (validation != null) {
      throw FormatException(validation);
    }
    await compose(withInstallationLink(
        'Moja Biblioteka — prośba o przedłużenie\n\nKsiążka: ${loan.title}\n'
        'Właściciel: ${loan.owner ?? 'Nie podano'}\n'
        'Obecny termin zwrotu: ${returnDateHistoryValue(loan.returnDate)}\n'
        'Proponowany termin zwrotu: ${formatReturnDate(date)}'));
  }

  Future<void> changeDate() async {
    final date = await pick('Nowy termin zwrotu');
    if (date == null || !mounted) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Zmienić lokalny termin?'),
                content: const Text(
                    'Ustaw termin uzgodniony z właścicielem. Zmiana dotyczy tylko tego urządzenia.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Anuluj')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Potwierdź')),
                ]));
    if (confirmed != true) return;
    await widget.repository.changeBorrowedDueDate(loan, date);
    loan = (await widget.repository.borrowedLoans())
        .singleWhere((l) => l.loanId == loan.loanId && l.origin == loan.origin);
  }

  Future<void> ownerApproval() async {
    final date = await pick('Nowy termin zwrotu');
    if (date == null) return;
    // Existing transaction preserves owner history and reminder reconciliation.
    await widget.repository.approveReadableExtension(loan, date);
    loan = await widget.repository.loanInvitation(loan.bookId);
    await compose(withInstallationLink(
        'Moja Biblioteka — zatwierdzenie przedłużenia\n\n'
        'Książka: ${loan.title}\nNowy termin zwrotu: ${formatReturnDate(date)}'));
  }

  Future<void> sendInvitation() async {
    final controller = TextEditingController(text: loan.owner ?? '');
    final owner = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Właściciel'),
                content: TextField(
                    controller: controller,
                    maxLength: 120,
                    decoration: const InputDecoration(
                        labelText: 'Imię i nazwisko właściciela')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Anuluj')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, controller.text),
                      child: const Text('Dalej'))
                ]));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (owner == null) return;
    final name = ReadableLoan.field(owner, 'Właściciel', 120);
    loan = await widget.repository.loanInvitation(loan.bookId);
    await compose(readableInvitation(LoanTransfer(
        transferId: loan.transferId,
        loanId: loan.loanId,
        bookId: loan.bookId,
        title: loan.title,
        author: loan.author,
        owner: name,
        isbn: loan.isbn,
        borrowedAt: loan.borrowedAt,
        returnDate: loan.returnDate,
        issuedAt: loan.issuedAt,
        revision: loan.revision)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Wiadomości o wypożyczeniu')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(loan.title, style: Theme.of(context).textTheme.headlineSmall),
        Text(loan.author),
        Text('Właściciel: ${loan.owner ?? 'Nie podano'}'),
        Text('Data wypożyczenia: ${formatReturnDate(loan.borrowedAt)}'),
        Text('Termin zwrotu: ${returnDateHistoryValue(loan.returnDate)}'),
        if (loan.isbn != null) Text('ISBN: ${loan.isbn}'),
        Text('Źródło: ${switch (loan.origin) {
          'sms' => 'SMS',
          'manual' => 'Wpis ręczny',
          _ => 'QR'
        }}'),
        if (widget.ownerSide) ...[
          FilledButton(
              onPressed: busy ? null : () => run(sendInvitation),
              child: const Text('Wyślij informacje SMS')),
          OutlinedButton(
              onPressed: busy ? null : () => run(ownerApproval),
              child: const Text('Zatwierdź przedłużenie')),
          OutlinedButton(
              onPressed: busy
                  ? null
                  : () => run(() => compose(withInstallationLink(
                      'Moja Biblioteka — odmowa przedłużenia\n\nKsiążka: ${loan.title}\n'
                      'Termin zwrotu pozostaje bez zmian: ${returnDateHistoryValue(loan.returnDate)}'))),
              child: const Text('Odmów przedłużenia SMS')),
        ] else ...[
          FilledButton(
              onPressed: busy ? null : () => run(request),
              child: const Text('Poproś o przedłużenie')),
          OutlinedButton(
              onPressed: busy ? null : () => run(changeDate),
              child: const Text('Zmień termin zwrotu')),
        ],
        if (error != null) Text(error!),
        FutureBuilder<List<Map<String, Object?>>>(
            future: history,
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const SizedBox.shrink();
              }
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Wcześniejsze wiadomości'),
                    for (final row in snapshot.data!)
                      ListTile(
                          title: Text(messageState(row['state']! as String)),
                          subtitle: Text(
                              'Proponowany termin zwrotu: ${formatReturnDate(LoanMessage.decode(row['request']! as String).newDate)}')),
                  ]);
            }),
      ]));
}
