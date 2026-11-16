import 'package:flutter/material.dart';
import '../data/library_repository.dart';
import '../models/readable_loan.dart';
import '../models/return_date.dart';

class BorrowedEntryScreen extends StatefulWidget {
  const BorrowedEntryScreen(
      {required this.repository, required this.fromSms, super.key});
  final LibraryRepository repository;
  final bool fromSms;
  @override
  State<BorrowedEntryScreen> createState() => _BorrowedEntryScreenState();
}

class _BorrowedEntryScreenState extends State<BorrowedEntryScreen> {
  final sms = TextEditingController();
  final title = TextEditingController(),
      author = TextEditingController(),
      owner = TextEditingController(),
      isbn = TextEditingController();
  late DateTime borrowed = calendarDate(widget.repository.currentTime);
  DateTime? due;
  String? source, error;
  bool saving = false;
  @override
  void dispose() {
    for (final c in [sms, title, author, owner, isbn]) {
      c.dispose();
    }
    super.dispose();
  }

  void parse() {
    try {
      final data =
          ReadableLoan.parse(sms.text, today: widget.repository.currentTime);
      setState(() {
        source = sms.text;
        title.text = data.title;
        author.text = data.author;
        owner.text = data.owner;
        isbn.text = data.isbn ?? '';
        borrowed = data.borrowedAt;
        due = data.returnDate;
        error = null;
      });
    } on FormatException catch (e) {
      setState(() => error = e.message);
    }
  }

  Future<void> pick(bool borrowing) async {
    final date = await showDatePicker(
        context: context,
        locale: const Locale('pl'),
        initialDate: (borrowing ? borrowed : due) ?? borrowed,
        firstDate: DateTime(1900),
        lastDate: DateTime(2200, 12, 31));
    if (date != null && mounted) {
      setState(() {
        if (borrowing) {
          borrowed = date;
        } else {
          due = date;
        }
      });
    }
  }

  Future<void> save() async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.repository.saveLocalBorrowed(
          ReadableLoan(
              title: title.text,
              author: author.text,
              owner: owner.text,
              borrowedAt: borrowed,
              returnDate: due,
              isbn: isbn.text),
          origin: widget.fromSms ? 'sms' : 'manual',
          smsSource: source);
      if (mounted) Navigator.pop(context);
    } on FormatException catch (e) {
      if (mounted) {
        setState(() => error = e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Nie udało się zapisać wpisu.');
      }
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  Widget field(TextEditingController c, String label, int max) => TextField(
      controller: c,
      maxLength: max,
      decoration: InputDecoration(labelText: label));
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar:
          AppBar(title: Text(widget.fromSms ? 'Dodaj z SMS' : 'Dodaj ręcznie')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        if (widget.fromSms && source == null) ...[
          TextField(
              controller: sms,
              maxLength: ReadableLoan.maxLength,
              minLines: 6,
              maxLines: 12,
              decoration:
                  const InputDecoration(labelText: 'Wklej wiadomość SMS')),
          FilledButton(
              onPressed: parse, child: const Text('Odczytaj wiadomość')),
        ] else ...[
          if (widget.fromSms)
            const Text('Sprawdź i popraw dane przed zapisaniem.'),
          field(title, 'Tytuł', 240),
          field(author, 'Autor', 160),
          field(owner, 'Właściciel', 120),
          ListTile(
              title: const Text('Data wypożyczenia'),
              subtitle: Text(formatReturnDate(borrowed)),
              onTap: () => pick(true)),
          ListTile(
              title: const Text('Termin zwrotu'),
              subtitle: Text(returnDateHistoryValue(due)),
              onTap: () => pick(false)),
          if (due != null)
            TextButton(
                onPressed: () => setState(() => due = null),
                child: const Text('Usuń termin zwrotu')),
          field(isbn, 'ISBN (opcjonalnie)', 32),
          FilledButton(
              onPressed: saving ? null : save,
              child: const Text('Potwierdź i zapisz')),
        ],
        if (error != null) Text(error!),
      ]));
}
