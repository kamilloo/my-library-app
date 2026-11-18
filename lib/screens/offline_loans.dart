import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../data/library_repository.dart';
import '../models/loan_transfer.dart';
import 'owner_name_dialog.dart';
import '../models/return_date.dart';
import 'loan_messaging.dart';
import 'borrowed_entry.dart';

String loanDate(DateTime? date) => returnDateHistoryValue(date);

class LoanQrScreen extends StatefulWidget {
  const LoanQrScreen(
      {required this.loan, this.borrower, this.repository, super.key});
  final LoanTransfer loan;
  final String? borrower;
  final LibraryRepository? repository;

  @override
  State<LoanQrScreen> createState() => _LoanQrScreenState();
}

class _LoanQrScreenState extends State<LoanQrScreen> {
  late LoanTransfer loan = widget.loan;
  bool busy = false;

  Future<void> editOwner() async {
    setState(() => busy = true);
    try {
      final preferred = await widget.repository!.preferredOwnerName();
      if (!mounted) return;
      final input = await showOwnerNameDialog(
        context,
        requiredName: false,
        initialName: preferred ?? '',
      );
      if (input == null || !mounted) return;
      await widget.repository!.savePreferredOwnerName(input);
      final updated = await widget.repository!.loanInvitation(loan.bookId);
      if (mounted) setState(() => loan = updated);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Nie udało się odświeżyć kodu. Spróbuj ponownie.')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Kod wypożyczenia')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          Text(loan.title, style: Theme.of(context).textTheme.headlineSmall),
          Text(loan.author),
          if (widget.borrower != null) Text('Wypożyczono: ${widget.borrower}'),
          Text('Właściciel: ${loan.owner ?? 'Nie podano'}'),
          if (widget.repository != null)
            OutlinedButton(
                onPressed: busy ? null : editOwner,
                child: const Text('Edytuj nazwę właściciela')),
          const Text(
              'Nazwa jest opcjonalna i będzie używana w kolejnych kodach QR. '
              'To informacja podana przez użytkownika, bez weryfikacji tożsamości lub własności.'),
          Text('Data wypożyczenia: ${loanDate(loan.borrowedAt)}'),
          Text('Termin zwrotu: ${loanDate(loan.returnDate)}'),
          const SizedBox(height: 16),
          Center(
              child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Semantics(
                label: 'Kod QR wypożyczenia',
                image: true,
                child: QrImageView(
                    data: loan.encode(),
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.all(24),
                    errorCorrectionLevel: QrErrorCorrectLevel.M)),
          )),
          FilledButton(
              onPressed: () async {
                try {
                  await const MethodChannel('my_library/offline_loans')
                      .invokeMethod<void>('share', {
                    'text': 'Informacje o wypożyczeniu książki „${loan.title}”. Potrzebujesz aplikacji Moja Biblioteka. '
                        'Jeśli jej nie masz, poproś właściciela o zaufane źródło instalacji. '
                        'Po instalacji otwórz „Pożyczone” i „Wklej kod wypożyczenia”. '
                        'Skopiuj sam kod poniżej:\n\n${loan.encode()}',
                  });
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text(
                            'Nie udało się udostępnić informacji. Użyj „Kopiuj kod”.')));
                  }
                }
              },
              child: const Text('Udostępnij informacje')),
          OutlinedButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: loan.encode()));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Skopiowano kod')));
                }
              },
              child: const Text('Kopiuj kod')),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Zamknij')),
        ]),
      );
}

class BorrowedLoansScreen extends StatefulWidget {
  const BorrowedLoansScreen({required this.repository, super.key});
  final LibraryRepository repository;
  @override
  State<BorrowedLoansScreen> createState() => _BorrowedLoansScreenState();
}

class _BorrowedLoansScreenState extends State<BorrowedLoansScreen> {
  late Future<List<LoanTransfer>> loans = widget.repository.borrowedLoans();
  bool busy = false;
  void reload() => setState(() {
        loans = widget.repository.borrowedLoans();
      });

  Future<void> importCode(String code) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final loan = LoanTransfer.decode(code);
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('Podgląd wypożyczenia'),
                  content: SingleChildScrollView(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(loan.title),
                        Text(loan.author),
                        Text('Właściciel: ${loan.owner ?? 'Nie podano'}'),
                        Text('Data wypożyczenia: ${loanDate(loan.borrowedAt)}'),
                        Text('Termin zwrotu: ${loanDate(loan.returnDate)}'),
                        const SizedBox(height: 12),
                        const Text(
                            'Informacje pochodzą z innego urządzenia i nie można ich niezależnie zweryfikować. '
                            'Kod nie jest dowodem własności ani tożsamości.'),
                      ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Anuluj')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Dodaj do pożyczonych')),
                  ]));
      if (confirmed != true) return;
      await widget.repository.importLoan(loan);
      if (mounted) reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error is FormatException
                ? error.message
                : 'Nie udało się zapisać wypożyczenia.')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> paste() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Wklej kod wypożyczenia'),
                content: TextField(
                    controller: controller,
                    maxLength: LoanTransfer.maxLength,
                    maxLines: 5,
                    decoration:
                        const InputDecoration(labelText: 'Kod wypożyczenia')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Anuluj')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, controller.text),
                      child: const Text('Dalej')),
                ]));
    // The dialog may still be animating while its field detaches.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (code != null && mounted) await importCode(code);
  }

  Future<void> addEntry(bool sms) async {
    await Navigator.push<void>(
        context,
        MaterialPageRoute(
            builder: (_) => BorrowedEntryScreen(
                repository: widget.repository, fromSms: sms)));
    if (mounted) reload();
  }

  Future<void> scan() async {
    final code = await Navigator.push<String>(
        context, MaterialPageRoute(builder: (_) => const LoanScannerScreen()));
    if (code != null && mounted) await importCode(code);
  }

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.fromLTRB(20, 22, 20, 110), children: [
        Text('Pożyczone', style: Theme.of(context).textTheme.headlineSmall),
        FilledButton.icon(
            onPressed: busy ? null : scan,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Skanuj kod QR')),
        FilledButton(
            onPressed: busy ? null : () => addEntry(true),
            child: const Text('Dodaj z SMS')),
        FilledButton(
            onPressed: busy ? null : () => addEntry(false),
            child: const Text('Dodaj ręcznie')),
        OutlinedButton(
            onPressed: busy ? null : paste,
            child: const Text('Wklej kod wypożyczenia')),
        FutureBuilder<List<LoanTransfer>>(
            future: loans,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Text(
                    'Nie udało się odczytać pożyczonych książek.');
              }
              if (!snapshot.hasData) return const LinearProgressIndicator();
              if (snapshot.data!.isEmpty) {
                return const Text('Brak pożyczonych książek.');
              }
              return Column(
                  children: snapshot.data!
                      .map((loan) => Card(
                              child: ListTile(
                            onTap: busy
                                ? null
                                : () async {
                                    await Navigator.push<void>(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) => LoanMessagingScreen(
                                                repository: widget.repository,
                                                loan: loan,
                                                ownerSide: false)));
                                    if (mounted) reload();
                                  },
                            title: Text(loan.title),
                            subtitle: Text(
                                '${loan.author}\nWłaściciel: ${loan.owner ?? 'Nie podano'}\n'
                                'Data wypożyczenia: ${loanDate(loan.borrowedAt)}\nTermin zwrotu: ${loanDate(loan.returnDate)}'),
                            trailing: IconButton(
                                tooltip: 'Usuń lokalny zapis',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: busy
                                    ? null
                                    : () async {
                                        final confirmed = await showDialog<
                                                bool>(
                                            context: context,
                                            builder: (context) => AlertDialog(
                                                    title: const Text(
                                                        'Usunąć lokalny zapis?'),
                                                    content: const Text(
                                                        'Nie zmieni to danych na urządzeniu właściciela.'),
                                                    actions: [
                                                      TextButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                  context),
                                                          child: const Text(
                                                              'Anuluj')),
                                                      FilledButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                  context,
                                                                  true),
                                                          child: const Text(
                                                              'Usuń')),
                                                    ]));
                                        if (confirmed != true) return;
                                        await widget.repository
                                            .deleteBorrowedLoan(loan.loanId,
                                                origin: loan.origin);
                                        if (mounted) reload();
                                      }),
                          )))
                      .toList());
            }),
      ]);
}

class LoanScannerScreen extends StatefulWidget {
  const LoanScannerScreen({super.key});
  @override
  State<LoanScannerScreen> createState() => _LoanScannerScreenState();
}

class _LoanScannerScreenState extends State<LoanScannerScreen>
    with WidgetsBindingObserver {
  final controller =
      MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool handled = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> changeCameraState(bool resume) async {
    try {
      if (resume) {
        await controller.start();
      } else {
        await controller.stop();
      }
    } catch (_) {
      // Camera startup errors are rendered by MobileScanner; manual import stays available.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!controller.value.hasCameraPermission) return;
    if (state == AppLifecycleState.resumed && !handled) {
      unawaited(changeCameraState(true));
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(changeCameraState(false));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Skanuj kod QR')),
        body: Column(children: [
          Expanded(
              child: MobileScanner(
                  controller: controller,
                  useAppLifecycleState: false,
                  errorBuilder: (context, error) => const Center(
                      child: Text(
                          'Brak dostępu do aparatu. Wróć i wybierz „Wklej kod wypożyczenia”.')),
                  onDetect: (capture) {
                    if (handled) return;
                    for (final barcode in capture.barcodes) {
                      final raw = barcode.rawValue;
                      if (raw == null) continue;
                      try {
                        LoanTransfer.decode(raw);
                        handled = true;
                        Navigator.pop(context, raw);
                        return;
                      } on FormatException {
                        handled = true;
                        unawaited(changeCameraState(false));
                        showDialog<void>(
                            context: context,
                            builder: (context) => AlertDialog(
                                  title: const Text(
                                      'Nieprawidłowy kod wypożyczenia'),
                                  actions: [
                                    TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Skanuj inny kod'))
                                  ],
                                )).whenComplete(() {
                          if (mounted) {
                            handled = false;
                            if (WidgetsBinding.instance.lifecycleState ==
                                AppLifecycleState.resumed) {
                              unawaited(changeCameraState(true));
                            }
                          }
                        });
                        return;
                      }
                    }
                  })),
          const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Umieść kod QR wypożyczenia w aparacie')),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Wróć do ręcznego wklejania kodu')),
        ]),
      );
}
