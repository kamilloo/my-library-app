import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:my_library/main.dart';
import 'package:my_library/models/open_library_search.dart';
import 'package:my_library/services/open_library_service.dart';

import 'cover_form_test.dart' show Repository;
import 'manual_isbn_lookup_test.dart' show LookupService;

class TestScanner extends MobileScannerPlatform {
  final captures = StreamController<BarcodeCapture>.broadcast();
  int starts = 0;
  int stops = 0;
  int disposals = 0;

  @override
  Stream<BarcodeCapture> get barcodesStream => captures.stream;

  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();

  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();

  @override
  Widget buildCameraView() => const SizedBox.expand();

  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) async {
    starts++;
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.off,
      size: Size(640, 480),
    );
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }

  void capture(BarcodeFormat format, String value) {
    captures.add(BarcodeCapture(
      barcodes: [Barcode(format: format, rawValue: value)],
    ));
  }
}

void main() {
  for (final retry in [false, true]) {
    testWidgets('scanned ISBN remains usable offline (retry: $retry)',
        (tester) async {
      final platform = MobileScannerPlatform.instance;
      final scanner = TestScanner();
      MobileScannerPlatform.instance = scanner;
      await tester.binding.setSurfaceSize(const Size(900, 1800));
      addTearDown(() async {
        MobileScannerPlatform.instance = platform;
        await scanner.captures.close();
        await tester.binding.setSurfaceSize(null);
      });

      final repository = Repository();
      final service = LookupService()
        ..response = () async =>
            throw const OpenLibrarySearchException(openLibraryNetworkMessage);
      await tester.pumpWidget(MaterialApp(
        home: AddBookScreen(repository: repository, isbnService: service),
      ));
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Ręczny tytuł');
      await tester.enterText(fields.at(1), 'Ręczny autor');
      await tester.tap(find.text('Skanuj kod kreskowy lub QR'));
      await tester.pumpAndSettle();
      scanner.capture(BarcodeFormat.ean13, '9780525559475');
      await tester.pumpAndSettle();
      expect(service.calls, isEmpty);
      expect(find.byType(MobileScanner), findsOneWidget);

      const isbn = '9780525559474';
      scanner.capture(
        retry ? BarcodeFormat.qrCode : BarcodeFormat.ean13,
        retry ? '978-0-525-55947-4' : isbn,
      );
      await tester.pumpAndSettle();

      if (kIsWeb) {
        expect(service.calls, isEmpty);
        expect(find.byType(MobileScanner), findsNothing);
      } else {
        expect(service.calls, [isbn]);
        expect(scanner.stops, 1);
        expect(find.text(openLibraryNetworkMessage), findsOneWidget);
        await tester.tap(find.text('Wpisz dane ręcznie'));
        await tester.pumpAndSettle();
      }
      expect(scanner.disposals, 1);
      expect(tester.widget<TextFormField>(fields.at(2)).controller!.text, isbn);

      if (retry) {
        if (kIsWeb) {
          await tester.tap(find.text('Pobierz dane książki'));
          await tester.pumpAndSettle();
          expect(find.text(openLibraryNetworkMessage), findsOneWidget);
        }
        service.response = () async => const OpenLibraryBook(
            title: 'Remote title', author: 'Remote author');
        await tester.tap(
            find.text(kIsWeb ? 'Spróbuj ponownie' : 'Pobierz dane książki'));
        await tester.pumpAndSettle();
        expect(service.calls, [isbn, isbn]);
        expect(scanner.starts, 1);
      }

      final save = find.widgetWithText(FilledButton, 'Zapisz książkę');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(repository.savedBarcode, isbn);
      expect(repository.savedTitle, 'Ręczny tytuł');
      expect(repository.savedAuthor, 'Ręczny autor');
    });
  }
}
