import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/open_library_service.dart';

class ScannedBook {
  const ScannedBook({required this.isbn, required this.book});

  final String isbn;
  final OpenLibraryBook book;
}

class ScanBookScreen extends StatefulWidget {
  const ScanBookScreen({super.key});

  @override
  State<ScanBookScreen> createState() => _ScanBookScreenState();
}

class _ScanBookScreenState extends State<ScanBookScreen> {
  final controller = MobileScannerController(
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.qrCode,
    ],
  );
  final service = OpenLibraryService();

  bool lookingUp = false;
  bool torchEnabled = false;
  String? error;
  String? scannedIsbn;
  OpenLibraryBook? result;

  @override
  void dispose() {
    unawaited(controller.dispose());
    super.dispose();
  }

  Future<void> detect(BarcodeCapture capture) async {
    if (lookingUp || result != null) return;
    for (final barcode in capture.barcodes) {
      final isbn = normalizeIsbn(barcode.rawValue);
      if (isbn == null) continue;
      await lookup(isbn);
      return;
    }
  }

  Future<void> lookup(String isbn) async {
    setState(() {
      lookingUp = true;
      error = null;
      scannedIsbn = isbn;
    });
    await controller.stop();
    try {
      final book = await service.lookupByIsbn(isbn);
      if (!mounted) return;
      setState(() {
        result = book;
        error = book == null
            ? 'Nie znaleziono książki. Spróbuj ponownie lub wpisz dane ręcznie.'
            : null;
      });
    } on TimeoutException {
      if (mounted)
        setState(() => error =
            'Przekroczono czas wyszukiwania. Sprawdź połączenie i spróbuj ponownie.');
    } catch (_) {
      if (mounted)
        setState(() =>
            error = 'Nie udało się pobrać danych książki. Spróbuj ponownie.');
    } finally {
      if (mounted) setState(() => lookingUp = false);
    }
  }

  Future<void> retry() async {
    setState(() {
      result = null;
      error = null;
      scannedIsbn = null;
    });
    await controller.start();
  }

  Future<void> toggleTorch() async {
    await controller.toggleTorch();
    if (mounted) setState(() => torchEnabled = !torchEnabled);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('Skanuj ISBN'),
          actions: [
            IconButton(
              onPressed: toggleTorch,
              tooltip: torchEnabled ? 'Wyłącz latarkę' : 'Włącz latarkę',
              icon: Icon(
                  torchEnabled ? Icons.flashlight_off : Icons.flashlight_on),
            ),
          ],
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(controller: controller, onDetect: detect),
            const _ScannerOverlay(),
            if (lookingUp)
              const ColoredBox(
                color: Color(0x99000000),
                child: Center(
                    child: CircularProgressIndicator(color: Colors.white)),
              ),
            if (result != null)
              _ResultSheet(
                isbn: scannedIsbn!,
                book: result!,
                onRetry: retry,
                onConfirm: () => Navigator.pop(
                  context,
                  ScannedBook(isbn: scannedIsbn!, book: result!),
                ),
              ),
            if (error != null) _ErrorSheet(message: error!, onRetry: retry),
          ],
        ),
      );
}

String? normalizeIsbn(String? rawValue) {
  if (rawValue == null) return null;
  final value = rawValue.replaceAll(RegExp('[^0-9Xx]'), '').toUpperCase();
  if (value.length == 10 && _validIsbn10(value)) return value;
  if (value.length == 13 && _validIsbn13(value)) return value;
  return null;
}

bool _validIsbn10(String value) {
  var sum = 0;
  for (var index = 0; index < 10; index++) {
    final character = value[index];
    final digit = character == 'X' && index == 9 ? 10 : int.tryParse(character);
    if (digit == null) return false;
    sum += digit * (10 - index);
  }
  return sum % 11 == 0;
}

bool _validIsbn13(String value) {
  var sum = 0;
  for (var index = 0; index < 13; index++) {
    final digit = int.parse(value[index]);
    sum += digit * (index.isEven ? 1 : 3);
  }
  return sum % 10 == 0;
}

class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay();

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Column(
          children: [
            const Spacer(),
            Container(
              width: 280,
              height: 170,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Umieść kod ISBN w ramce',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
          ],
        ),
      );
}

class _ResultSheet extends StatelessWidget {
  const _ResultSheet({
    required this.isbn,
    required this.book,
    required this.onRetry,
    required this.onConfirm,
  });

  final String isbn;
  final OpenLibraryBook book;
  final VoidCallback onRetry;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Znaleziono książkę',
                      style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  if (book.coverUrl != null) ...[
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          book.coverUrl!,
                          width: 92,
                          height: 132,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  Text(book.title,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('${book.author} · ISBN $isbn'),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                          child: OutlinedButton(
                              onPressed: onRetry,
                              child: const Text('Skanuj ponownie'))),
                      const SizedBox(width: 10),
                      Expanded(
                          child: FilledButton(
                              onPressed: onConfirm,
                              child: const Text('Użyj danych'))),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _ErrorSheet extends StatelessWidget {
  const _ErrorSheet({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 14),
                  SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                          onPressed: onRetry,
                          child: const Text('Spróbuj ponownie'))),
                ],
              ),
            ),
          ),
        ),
      );
}
