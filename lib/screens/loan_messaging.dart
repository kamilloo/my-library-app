import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/library_repository.dart';
import '../models/book.dart';
import '../models/loan_transfer.dart';
import '../models/loan_message.dart';
import '../models/return_date.dart';
import '../services/loan_sms.dart';
import 'loan_extension_dialog.dart';

const smsPrivacy =
    'SMS może być płatny i nie jest szyfrowany od końca do końca. '
    'Wysyłanie jest ręczne. Otwarcie aplikacji SMS nie potwierdza wysłania ani dostarczenia.';

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
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Przygotowana wiadomość')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Text(smsPrivacy),
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
        const Text(
            'Numer służy tylko do uzupełnienia odbiorcy SMS. Zapis wymaga osobnego przycisku.'),
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
  List<Map<String, Object?>> records = [];
  bool busy = false;
  String? error;
  String get role => widget.ownerSide ? 'owner' : 'borrower';

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final rows = await widget.repository.messages(role, loanId: loan.loanId);
      if (mounted) setState(() => records = rows);
    } catch (_) {
      if (mounted) setState(() => error = 'Nie udało się odczytać wiadomości.');
    }
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      await refresh();
    } catch (e) {
      if (mounted) {
        setState(() => error = e is FormatException
            ? e.message
            : 'Nie udało się wykonać operacji. Odśwież dane i spróbuj ponownie.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> compose(String text, {String? requestId}) async {
    final phone = await widget.repository.contact(role, loan.loanId);
    if (!mounted) return;
    await Navigator.push<void>(
        context,
        MaterialPageRoute(
            builder: (_) => SmsMessageScreen(
                text: text,
                initialPhone: phone ?? '',
                onSavePhone: (p) =>
                    widget.repository.saveContact(role, loan.loanId, p),
                onSent: requestId == null
                    ? null
                    : () => widget.repository.markRequestSent(requestId))));
  }

  Future<String?> paste(String title) async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
                title: Text(title),
                content: TextField(
                    controller: controller,
                    maxLength: LoanTransfer.maxLength,
                    maxLines: 5,
                    decoration:
                        const InputDecoration(labelText: 'Wklej sam kod')),
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
    return code;
  }

  Future<void> request() async {
    // A fresh local record prevents presets being calculated from an old screen.
    final loans = await widget.repository.borrowedLoans();
    loan = loans.singleWhere((l) => l.loanId == loan.loanId);
    if (!mounted) return;
    final result = await showDialog<LoanMessage>(
        context: context,
        builder: (_) => LoanExtensionDialog(
            repository: widget.repository,
            requestLoanId: loan.loanId,
            book: Book(
                id: loan.bookId,
                title: loan.title,
                author: loan.author,
                createdAt: loan.borrowedAt,
                updatedAt: loan.issuedAt,
                returnDate: loan.returnDate)));
    if (result != null && mounted) {
      await compose(extensionMessage(result, loan.title),
          requestId: result.requestId);
    }
  }

  Future<void> importRequest() async {
    final code = await paste('Odczytaj prośbę o przedłużenie');
    if (code == null || !mounted) return;
    final request = LoanMessage.decode(code);
    if (request.loanId != loan.loanId) {
      throw const FormatException('Kod dotyczy innego wypożyczenia.');
    }
    final book = await widget.repository.previewExtension(request);
    if (!mounted) return;
    final approved = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Niezweryfikowana prośba'),
                content: SingleChildScrollView(
                    child: Text(
                        '${book.title}\nWypożyczono: ${book.borrowedBy}\nObecny termin: ${returnDateHistoryValue(book.returnDate)}\n'
                        'Żądany termin: ${formatReturnDate(request.newDate)}\nID: ${request.requestId}\n'
                        'Kod nie dowodzi tożsamości nadawcy. Zweryfikuj prośbę we własnym zakresie.')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Anuluj')),
                  OutlinedButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Odrzuć prośbę')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Zatwierdź przedłużenie'))
                ]));
    if (approved == null) return;
    final decision = await widget.repository.decideExtension(request, approved);
    // The decision is already committed. This screen offers explicit composition.
    await refresh();
    if (mounted) await compose(extensionMessage(decision, loan.title));
  }

  Future<void> importApproval() async {
    final code = await paste('Wklej potwierdzenie przedłużenia');
    if (code == null || !mounted) return;
    final message = LoanMessage.decode(code);
    if (message.loanId != loan.loanId) {
      throw const FormatException('Kod dotyczy innego wypożyczenia.');
    }
    final old = await widget.repository.previewConfirmation(message);
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Niezweryfikowane potwierdzenie'),
                content: Text(
                    '${old.title}\nObecny termin: ${returnDateHistoryValue(old.returnDate)}\n'
                    'Zatwierdzony termin: ${formatReturnDate(message.newDate)}\nID: ${message.requestId}\n'
                    'Aplikacja nie może udowodnić, że kod pochodzi od właściciela. Brak automatycznej synchronizacji.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Anuluj')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Zastosuj nowy termin'))
                ]));
    if (confirmed != true) return;
    await widget.repository.importConfirmation(message);
    loan = (await widget.repository.borrowedLoans())
        .singleWhere((l) => l.loanId == loan.loanId);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Wiadomości o wypożyczeniu')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(loan.title, style: Theme.of(context).textTheme.headlineSmall),
        const Text(smsPrivacy),
        const Text(
            'Dane są lokalne. Brak automatycznej synchronizacji. Kody nie potwierdzają tożsamości.'),
        if (widget.ownerSide) ...[
          FilledButton(
              onPressed: busy
                  ? null
                  : () => run(() async {
                        loan =
                            await widget.repository.loanInvitation(loan.bookId);
                        await compose(invitationMessage(loan));
                      }),
              child: const Text('Wyślij informacje SMS')),
          OutlinedButton(
              onPressed: busy ? null : () => run(importRequest),
              child: const Text('Odczytaj prośbę o przedłużenie')),
        ] else ...[
          Text('Zapisany termin: ${returnDateHistoryValue(loan.returnDate)}'),
          FilledButton(
              onPressed: busy ? null : () => run(request),
              child: const Text('Poproś o przedłużenie')),
          OutlinedButton(
              onPressed: busy ? null : () => run(importApproval),
              child: const Text('Wklej potwierdzenie przedłużenia')),
        ],
        if (error != null) Text(error!),
        for (final row in records)
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(messageState(row['state']! as String)),
                        Text('ID: ${row['request_id']}'),
                        Text(
                            'Żądany termin: ${formatReturnDate(LoanMessage.decode(row['request']! as String).newDate)}'),
                        OutlinedButton(
                            onPressed: busy
                                ? null
                                : () => run(() async {
                                      final message = LoanMessage.decode(
                                          (row['decision'] ?? row['request'])!
                                              as String);
                                      await compose(
                                          extensionMessage(message, loan.title),
                                          requestId: row['decision'] == null &&
                                                  !widget.ownerSide
                                              ? message.requestId
                                              : null);
                                    }),
                            child: Text(row['state'] == 'approved'
                                ? 'Wyślij potwierdzenie SMS'
                                : 'Otwórz wiadomość')),
                      ]))),
      ]));
}
