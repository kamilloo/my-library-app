import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/data/library_database.dart';
import 'package:my_library/data/library_repository.dart';
import 'package:my_library/main.dart';
import 'package:my_library/models/loan_transfer.dart';
import 'package:my_library/models/book.dart';
import 'package:my_library/screens/offline_loans.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fixtures/legacy_library_schema.dart';

LoanTransfer fixture(
        {String loan = 'loan-1', int revision = 1, DateTime? due}) =>
    LoanTransfer(
        transferId: 'transfer-$loan',
        loanId: loan,
        bookId: 'owner-book',
        title: 'Zażółć gęślą jaźń',
        author: 'Łukasz Ćma',
        owner: 'Małgorzata',
        isbn: '9780306406157',
        borrowedAt: DateTime(2026, 1, 2),
        issuedAt: DateTime.utc(2026, 1, revision + 2),
        returnDate: due,
        revision: revision);

String raw(Map<String, Object?> map) =>
    LoanTransfer.prefix + base64Url.encode(utf8.encode(jsonEncode(map)));

class CameraPlatform extends MobileScannerPlatform {
  bool denied = false;
  int starts = 0;
  int stops = 0;
  final captures = StreamController<BarcodeCapture?>.broadcast();
  @override
  Stream<BarcodeCapture?> get barcodesStream => captures.stream;
  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();
  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();
  @override
  Widget buildCameraView() => const SizedBox.expand();
  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) async {
    starts++;
    if (denied) {
      throw const MobileScannerException(
          errorCode: MobileScannerErrorCode.permissionDenied);
    }
    return const MobileScannerViewAttributes(
        cameraDirection: CameraFacing.back,
        currentTorchMode: TorchState.off,
        size: Size(640, 480));
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() async {}
  @override
  Future<void> updateScanWindow(Rect? window) async {}
}

class WidgetRepository extends LibraryRepository {
  final imported = <LoanTransfer>[];
  Book book = Book(
      id: 'b',
      title: 'T',
      author: 'A',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026));
  int lendCalls = 0;
  @override
  Future<List<LoanTransfer>> borrowedLoans() async => List.of(imported);
  @override
  Future<void> importLoan(LoanTransfer loan) async {
    imported.add(loan);
  }

  @override
  Future<List<Book>> books() async => [book];
  @override
  Future<List<HistoryEntry>> historyForBook(String id) async => [];
  @override
  Future<void> lendBook(Book original, String borrower, DateTime? due) async {
    lendCalls++;
    book = book.copyWith(
        status: BookStatus.borrowed,
        borrowedBy: borrower,
        borrowedDate: DateTime(2026, 1, 2),
        returnDate: due);
  }

  @override
  Future<LoanTransfer> loanInvitation(String id) async => fixture();
}

void main() {
  setUpAll(sqfliteFfiInit);
  test('Polish UTF-8 round trip is deterministic and bounded', () {
    final loan = fixture(due: DateTime(2027));
    expect(LoanTransfer.decode(loan.encode()).encode(), loan.encode());
    expect(LoanTransfer.decode(loan.encode()).title, 'Zażółć gęślą jaźń');
    expect(loan.encode().length, lessThan(1000));
  });
  test('optional fields and absent due date', () {
    final loan = LoanTransfer(
        transferId: 't',
        loanId: 'l',
        bookId: 'b',
        title: 'Tytuł',
        author: 'Autor',
        borrowedAt: DateTime(2026),
        issuedAt: DateTime.utc(2026),
        revision: 1);
    final parsed = LoanTransfer.decode(loan.encode());
    expect(parsed.owner, isNull);
    expect(parsed.isbn, isNull);
    expect(parsed.returnDate, isNull);
  });
  for (final entry in <String, Object?>{
    'v': 2,
    't': 'extension_request',
    'revision': 0,
    'title': '',
    'author': List.filled(161, 'a').join(),
    'isbn': '123',
    'borrowed': 'yesterday',
    'due': '2020-01-01',
    'loan': null,
    'owner': 'private\npath',
  }.entries) {
    test('reject invalid ${entry.key}', () {
      expect(
          () => LoanTransfer.decode(
              raw({...fixture().toJson(), entry.key: entry.value})),
          throwsFormatException);
    });
  }
  test('reject fractional version and invalid calendar/time values', () {
    for (final map in [
      {...fixture().toJson(), 'v': 1.0},
      {...fixture().toJson(), 'borrowed': '2026-02-30T12:00:00'},
      {...fixture().toJson(), 'issued': '2026-01-03T24:00:00Z'},
      {...fixture().toJson(), 'issued': '2026-01-03T12:00:00'},
    ]) {
      expect(() => LoanTransfer.decode(raw(map)), throwsFormatException);
    }
  });
  test('reject malformed and oversized input', () {
    for (final code in [
      'abc',
      'moja-biblioteka:***',
      raw({'v': 1}),
      'moja-biblioteka:${List.filled(2500, 'a').join()}'
    ]) {
      expect(() => LoanTransfer.decode(code), throwsFormatException);
    }
  });

  late LibraryDatabase database;
  late LibraryRepository repository;
  setUp(() {
    database = LibraryDatabase.inMemory(databaseFactoryFfi);
    repository = LibraryRepository(
        database: database, clock: () => DateTime(2026, 1, 2, 12));
  });
  tearDown(() async => (await database.database).close());

  test('duplicate imports preserve ownership and history; deletion is local',
      () async {
    final owned = await repository.addBook(
        title: 'Moja', author: 'Autor', barcode: '9780306406157');
    final before = (await repository.history()).length;
    await repository.importLoan(fixture());
    await repository.importLoan(fixture());
    expect(await repository.borrowedLoans(), hasLength(1));
    expect((await repository.books()).single.id, owned.id);
    expect(await repository.history(), hasLength(before));
    await repository.deleteBorrowedLoan(fixture().loanId);
    expect(await repository.borrowedLoans(), isEmpty);
    expect((await repository.books()).single.id, owned.id);
  });
  test('newer revisions update; stale and conflicting revisions are rejected',
      () async {
    final first = fixture();
    final next = fixture(revision: 2, due: DateTime(2027));
    await repository.importLoan(first);
    await repository.importLoan(next);
    await expectLater(repository.importLoan(first), throwsFormatException);
    final conflict =
        LoanTransfer.decode(raw({...next.toJson(), 'title': 'Conflict'}));
    await expectLater(repository.importLoan(conflict), throwsFormatException);
    final identity = LoanTransfer.decode(
        raw({...next.toJson(), 'book': 'other', 'revision': 3}));
    await expectLater(repository.importLoan(identity), throwsFormatException);
    expect((await repository.borrowedLoans()).single.encode(), next.encode());
  });
  test('failed revision update rolls back and retains borrower status',
      () async {
    await repository.importLoan(fixture());
    final db = await database.database;
    await db.update('borrowed_loans', {'local_status': 'returned'});
    await db.execute(
        "CREATE TRIGGER fail_import BEFORE UPDATE ON borrowed_loans BEGIN SELECT RAISE(ABORT, 'test'); END");
    await expectLater(
        repository.importLoan(fixture(revision: 2, due: DateTime(2027))),
        throwsA(isA<DatabaseException>()));
    expect((await repository.borrowedLoans()).single.revision, 1);
    await db.execute('DROP TRIGGER fail_import');
    await repository.importLoan(fixture(revision: 2, due: DateTime(2027)));
    expect(
        (await db.query('borrowed_loans')).single['local_status'], 'returned');
    final staleTime = LoanTransfer.decode(raw(
        {...fixture(revision: 3).toJson(), 'issued': '2026-01-01T00:00:00Z'}));
    await expectLater(repository.importLoan(staleTime), throwsFormatException);
  });
  test('different instances for one book remain separate', () async {
    await repository.importLoan(fixture());
    await repository.importLoan(fixture(loan: 'loan-2'));
    expect(await repository.borrowedLoans(), hasLength(2));
  });
  test('unique transfer collision rolls back', () async {
    await repository.importLoan(fixture());
    final conflict = LoanTransfer.decode(
        raw({...fixture(loan: 'other').toJson(), 'id': fixture().transferId}));
    await expectLater(
        repository.importLoan(conflict), throwsA(isA<DatabaseException>()));
    expect(await repository.borrowedLoans(), hasLength(1));
  });
  test(
      'QR reopen is read-only for books and history; relending changes instance',
      () async {
    var book = await repository.addBook(title: 'Żółw', author: 'Ćma');
    await repository.lendBook(book, 'Anna', null);
    book = (await repository.books()).single;
    final before = await (await database.database).query('books');
    final history = await (await database.database).query('history');
    final code = await repository.loanInvitation(book.id);
    expect(LoanTransfer.decode(code.encode()).returnDate, isNull);
    expect((await repository.loanInvitation(book.id)).encode(), code.encode());
    expect(await (await database.database).query('books'), before);
    expect(await (await database.database).query('history'), history);
    await repository.updateReturnDate(book.id, DateTime(2027));
    final updated = await repository.loanInvitation(book.id);
    expect(updated.loanId, code.loanId);
    expect(updated.revision, 2);
    await repository.returnBook((await repository.books()).single);
    await repository.lendBook((await repository.books()).single, 'Ola', null);
    final next = await repository.loanInvitation(book.id);
    expect(next.loanId, isNot(code.loanId));
  });
  test('failed loan transaction preserves books and history', () async {
    final book = await repository.addBook(title: 'T', author: 'A');
    final db = await database.database;
    await db.execute(
        "CREATE TRIGGER fail_history BEFORE INSERT ON history BEGIN SELECT RAISE(ABORT, 'test'); END");
    await expectLater(repository.lendBook(book, 'Anna', null),
        throwsA(isA<DatabaseException>()));
    expect((await repository.books()).single.status, book.status);
    expect(await repository.history(), hasLength(1));
    expect(await db.query('loan_transfers'), isEmpty);
  });
  test('v3 upgrade adds only new tables and preserves owned data', () async {
    final dir = await Directory.systemTemp.createTemp('offline-migration');
    final path = '${dir.path}/library.db';
    final legacy = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
            version: 3, onCreate: (db, _) => createLegacySchema(db, 3)));
    final book = Book(
        id: 'legacy',
        title: 'Żółw',
        author: 'Ćma',
        createdAt: DateTime(2025),
        updatedAt: DateTime(2026),
        status: BookStatus.borrowed,
        borrowedBy: 'Anna',
        borrowedDate: DateTime(2026, 1, 2));
    await legacy.insert('books', book.toMap());
    final original = await legacy.query('books');
    await legacy.close();
    final upgradedDatabase = LibraryDatabase.file(databaseFactoryFfi, path);
    final upgraded = await upgradedDatabase.database;
    expect(await upgraded.getVersion(), 4);
    expect(await upgraded.query('borrowed_loans'), isEmpty);
    expect(await upgraded.query('loan_transfers'), isEmpty);
    final owner = LibraryRepository(
        database: upgradedDatabase, clock: () => DateTime(2026, 1, 3));
    final code = await owner.loanInvitation(book.id);
    expect((await owner.loanInvitation(book.id)).encode(), code.encode());
    expect(await upgraded.query('books'), original);
    expect(await upgraded.query('history'), isEmpty);
    expect(await upgraded.query('owner_loan_instances'), hasLength(1));
    expect(await upgraded.rawQuery('PRAGMA integrity_check'), [
      {'integrity_check': 'ok'}
    ]);
    await upgraded.close();
    await dir.delete(recursive: true);
  });

  testWidgets(
      'manual import previews before confirmation and cancellation writes nothing',
      (tester) async {
    final repository = WidgetRepository();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: BorrowedLoansScreen(repository: repository))));
    await tester.pumpAndSettle();
    Future<void> preview() async {
      await tester.tap(find.text('Wklej kod wypożyczenia'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), fixture().encode());
      await tester.tap(find.text('Dalej'));
      await tester.pumpAndSettle();
    }

    await preview();
    expect(find.text('Podgląd wypożyczenia'), findsOneWidget);
    expect(await repository.borrowedLoans(), isEmpty);
    await tester.tap(find.text('Anuluj'));
    await tester.pumpAndSettle();
    expect(await repository.borrowedLoans(), isEmpty);
    await preview();
    await tester.tap(find.text('Dodaj do pożyczonych'));
    await tester.pumpAndSettle();
    expect(await repository.borrowedLoans(), hasLength(1));
    expect(find.text('Zażółć gęślą jaźń'), findsOneWidget);
    expect(find.text('Wypożycz książkę'), findsNothing);
  });
  testWidgets('QR renders on small screens with accessible label',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: LoanQrScreen(loan: fixture())));
    expect(find.byType(QrImageView), findsOneWidget);
    expect(
        find.byWidgetPredicate((w) =>
            w is Semantics && w.properties.label == 'Kod QR wypożyczenia'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('camera denial offers manual fallback without any import',
      (tester) async {
    final previous = MobileScannerPlatform.instance;
    final camera = CameraPlatform()..denied = true;
    MobileScannerPlatform.instance = camera;
    addTearDown(() async {
      MobileScannerPlatform.instance = previous;
      await camera.captures.close();
    });
    final repository = WidgetRepository();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: BorrowedLoansScreen(repository: repository))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skanuj kod wypożyczenia'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Brak dostępu do aparatu'), findsOneWidget);
    await tester.tap(find.text('Wróć do ręcznego wklejania kodu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wklej kod wypożyczenia'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(repository.imported, isEmpty);
    await tester.tap(find.text('Anuluj'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'repeated camera detections open a single preview and cancellation is safe',
      (tester) async {
    final previous = MobileScannerPlatform.instance;
    final camera = CameraPlatform();
    MobileScannerPlatform.instance = camera;
    addTearDown(() async {
      MobileScannerPlatform.instance = previous;
      await camera.captures.close();
    });
    final repository = WidgetRepository();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: BorrowedLoansScreen(repository: repository))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skanuj kod wypożyczenia'));
    await tester.pumpAndSettle();
    final capture =
        BarcodeCapture(barcodes: [Barcode(rawValue: fixture().encode())]);
    camera.captures.add(capture);
    camera.captures.add(capture);
    await tester.pumpAndSettle();
    expect(find.text('Podgląd wypożyczenia'), findsOneWidget);
    expect(repository.imported, isEmpty);
    await tester.tap(find.text('Anuluj'));
    await tester.pumpAndSettle();
    expect(find.text('Skanuj kod wypożyczenia'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'scanner stops in background, resumes and can retry an invalid code',
      (tester) async {
    final previous = MobileScannerPlatform.instance;
    final camera = CameraPlatform();
    MobileScannerPlatform.instance = camera;
    addTearDown(() async {
      MobileScannerPlatform.instance = previous;
      await camera.captures.close();
    });
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () => Navigator.push<String>(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const LoanScannerScreen())),
                child: const Text('Open')))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(camera.starts, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(camera.stops, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(camera.starts, 2);
    camera.captures
        .add(const BarcodeCapture(barcodes: [Barcode(rawValue: 'invalid')]));
    await tester.pumpAndSettle();
    expect(find.text('Nieprawidłowy kod wypożyczenia'), findsOneWidget);
    await tester.tap(find.text('Skanuj inny kod'));
    await tester.pumpAndSettle();
    camera.captures
        .add(BarcodeCapture(barcodes: [Barcode(rawValue: fixture().encode())]));
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('owner confirms once and reopens QR without lending again',
      (tester) async {
    final repository = WidgetRepository();
    await tester.pumpWidget(MaterialApp(
        home:
            BookDetailsScreen(book: repository.book, repository: repository)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Wypożycz książkę'), 300);
    await tester.tap(find.text('Wypożycz książkę'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Anna');
    await tester.tap(find.text('Bez terminu zwrotu'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Dalej — sprawdź dane'));
    await tester.tap(find.text('Dalej — sprawdź dane'));
    await tester.pumpAndSettle();
    expect(repository.lendCalls, 0);
    await tester
        .tap(find.widgetWithText(FilledButton, 'Potwierdź wypożyczenie'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
    expect(repository.lendCalls, 1);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Pokaż kod QR'), -300);
    await tester.tap(find.text('Pokaż kod QR'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
    expect(repository.lendCalls, 1);
  });
  testWidgets('cancel before owner review creates no loan', (tester) async {
    final repository = WidgetRepository();
    final book = repository.book;
    await tester.pumpWidget(MaterialApp(
        home: BookDetailsScreen(book: book, repository: repository)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Wypożycz książkę'), 300);
    await tester.tap(find.text('Wypożycz książkę'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Anna');
    await tester.tap(find.text('Bez terminu zwrotu'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Dalej — sprawdź dane'));
    await tester.tap(find.text('Dalej — sprawdź dane'));
    await tester.pumpAndSettle();
    expect((await repository.books()).single.status, book.status);
    await tester.tap(find.text('Anuluj'));
    await tester.pumpAndSettle();
    expect(repository.lendCalls, 0);
    expect((await repository.books()).single.status, book.status);
  });
}
