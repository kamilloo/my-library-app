import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/data/library_database.dart';
import 'package:my_library/data/library_repository.dart';
import 'package:my_library/models/loan_transfer.dart';
import 'package:my_library/models/owner_name.dart';
import 'package:my_library/screens/offline_loans.dart';
import 'package:my_library/screens/loan_messaging.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'offline_loans_test.dart' show WidgetRepository, fixture;

class OwnerWidgetRepository extends WidgetRepository {
  String? name;
  int revision = 1;
  @override
  Future<String?> preferredOwnerName() async => name;
  @override
  Future<String?> contact(String role, String loanId) async => null;
  @override
  Future<void> savePreferredOwnerName(String input) async {
    name = validateOwnerName(input);
    revision++;
  }

  @override
  Future<LoanTransfer> loanInvitation(String id) async =>
      LoanTransfer.decode(LoanTransfer.prefix +
          base64Url.encode(utf8.encode(jsonEncode(
              {...fixture().toJson(), 'owner': name, 'revision': revision}))));
}

Future<void> pumpApp(WidgetTester tester, Widget app) async {
  if (const bool.fromEnvironment('OWNER_SCREENSHOTS')) {
    await tester.binding.setSurfaceSize(const Size(420, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }
  await tester
      .pumpWidget(RepaintBoundary(key: const Key('owner-capture'), child: app));
}

Future<void> capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('OWNER_SCREENSHOTS')) return;
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('owner-capture')));
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('docs/screenshots/task25/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    if (const bool.fromEnvironment('OWNER_SCREENSHOTS')) {
      TestWidgetsFlutterBinding.ensureInitialized();
      final loader = FontLoader('Roboto');
      loader.addFont(File(Platform.environment['OWNER_SCREENSHOT_FONT']!)
          .readAsBytes()
          .then((bytes) => ByteData.sublistView(bytes)));
      await loader.load();
      final icons = FontLoader('MaterialIcons');
      icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    }
  });
  test(
      'optional Polish display name trims and rejects controls before trimming',
      () {
    expect(validateOwnerName(''), isNull);
    expect(validateOwnerName('   '), isNull);
    expect(validateOwnerName('  Żaneta Łącka  '), 'Żaneta Łącka');
    expect(validateOwnerName('ą' * 120), 'ą' * 120);
    for (final input in [
      'a' * 121,
      '\nJan',
      'Jan\r',
      'Jan\tK',
      'Jan\u007f',
      'Jan\u0085',
      'Jan\u2028'
    ]) {
      expect(() => validateOwnerName(input), throwsFormatException);
    }
  });

  test('offline restart, revisions, import and unrelated data preservation',
      () async {
    final dir = await Directory.systemTemp.createTemp('owner-name');
    final path = '${dir.path}/library.db';
    var database = LibraryDatabase.file(databaseFactoryFfi, path);
    var repository = LibraryRepository(
        database: database, clock: () => DateTime(2026, 11, 16));
    expect(await repository.preferredOwnerName(), isNull);
    final book = await repository.addBook(title: 'Żółw', author: 'Ćma');
    await repository.lendBook(book, 'Borrower is not owner', DateTime(2027));
    var db = await database.database;
    final before = <String, List<Map<String, Object?>>>{};
    for (final table in [
      'books',
      'history',
      'return_reminders',
      'loan_messages',
      'loan_contacts'
    ]) {
      before[table] = await db.query(table);
    }
    final original = await repository.loanInvitation(book.id);
    expect(original.owner, isNull);
    await repository.importLoan(original);
    await repository.savePreferredOwnerName('  Żaneta Łącka  ');
    final named = await repository.loanInvitation(book.id);
    expect(named.owner, 'Żaneta Łącka');
    expect(LoanTransfer.decode(named.encode()).owner, named.owner);
    expect(named.revision, original.revision + 1);
    expect(named.transferId, original.transferId);
    expect(named.loanId, original.loanId);
    expect(named.bookId, original.bookId);
    expect(named.borrowedAt, original.borrowedAt);
    await repository.importLoan(named);
    expect((await repository.borrowedLoans()).single.owner, named.owner);
    await repository.savePreferredOwnerName('Żaneta Łącka');
    expect((await repository.loanInvitation(book.id)).encode(), named.encode());
    await expectLater(
        repository.savePreferredOwnerName('bad\n'), throwsFormatException);
    expect(await repository.preferredOwnerName(), named.owner);
    await db.close();
    database = LibraryDatabase.file(databaseFactoryFfi, path);
    repository = LibraryRepository(database: database);
    db = await database.database;
    expect(await repository.preferredOwnerName(), named.owner);
    expect((await repository.loanInvitation(book.id)).encode(), named.encode());
    expect((await repository.borrowedLoans()).single.owner, named.owner);
    for (final table in before.keys) {
      expect(await db.query(table), before[table], reason: table);
    }
    await repository.savePreferredOwnerName(' ');
    final cleared = await repository.loanInvitation(book.id);
    expect(cleared.owner, isNull);
    expect(cleared.revision, named.revision + 1);
    await repository.importLoan(cleared);
    expect((await repository.borrowedLoans()).single.owner, isNull);
    await expectLater(repository.importLoan(named), throwsFormatException);
    final another = await repository.addBook(title: 'Next', author: 'A');
    await repository.savePreferredOwnerName('Jan Kowalski');
    await repository.lendBook(another, 'B', null);
    expect((await repository.loanInvitation(another.id)).owner, 'Jan Kowalski');
    await db.close();
    await dir.delete(recursive: true);
  });

  test('v7 migration adds preference only and failed migration rolls back',
      () async {
    final dir = await Directory.systemTemp.createTemp('owner-v7');
    final path = '${dir.path}/library.db';
    var database = LibraryDatabase.file(databaseFactoryFfi, path);
    final repo = LibraryRepository(database: database);
    final book = await repo.addBook(title: 'Old', author: 'A');
    await repo.lendBook(book, 'B', null);
    await repo.loanInvitation(book.id);
    var db = await database.database;
    await db.execute('DROP TABLE local_preferences');
    await db.setVersion(7);
    final tables = (await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"))
        .map((r) => r['name']! as String)
        .toList();
    final before = <String, List<Map<String, Object?>>>{};
    for (final table in tables) {
      before[table] = await db.query(table);
    }
    await db.execute('CREATE TABLE local_preferences (sentinel TEXT)');
    await db.close();
    database = LibraryDatabase.file(databaseFactoryFfi, path);
    await expectLater(database.database, throwsA(isA<DatabaseException>()));
    db = await databaseFactoryFfi.openDatabase(path);
    expect(await db.getVersion(), 7);
    for (final table in tables) {
      expect(await db.query(table), before[table]);
    }
    await db.execute('DROP TABLE local_preferences');
    await db.close();
    database = LibraryDatabase.file(databaseFactoryFfi, path);
    db = await database.database;
    expect(await db.getVersion(), 8);
    expect(await db.query('local_preferences'), isEmpty);
    for (final table in tables) {
      expect(await db.query(table), before[table]);
    }
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    await db.close();
    await dir.delete(recursive: true);
  });

  test('QR decoder rejects owner controls and excessive names', () {
    for (final name in ['a' * 121, 'Jan\u007f', 'Jan\u0085', 'Jan\u2028']) {
      final code = LoanTransfer.prefix +
          base64Url.encode(
              utf8.encode(jsonEncode({...fixture().toJson(), 'owner': name})));
      expect(() => LoanTransfer.decode(code), throwsFormatException);
    }
  });

  for (final name in <String?>[null, 'Jan Kowalski']) {
    testWidgets('SMS name is explicitly editable and optional for $name',
        (tester) async {
      final repository = OwnerWidgetRepository()..name = name;
      final loan = await repository.loanInvitation('b');
      await pumpApp(
          tester,
          MaterialApp(
              debugShowCheckedModeBanner: false,
              home: LoanMessagingScreen(
                  repository: repository, loan: loan, ownerSide: true)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wyślij informacje SMS'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          name ?? '');
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.text('Dalej'));
      await tester.pumpAndSettle();
      final text =
          tester.widget<SelectableText>(find.byType(SelectableText)).data!;
      expect(text, contains('Właściciel: Nie podano'));
      expect(text, isNot(contains('moja-biblioteka:')));
      if (name != null) expect(text, isNot(contains(name)));
      expect(repository.name, name);
    });
  }

  test('old v1 payload with absent owner remains readable', () {
    final json = fixture().toJson()..remove('owner');
    final old = LoanTransfer.decode(
        LoanTransfer.prefix + base64Url.encode(utf8.encode(jsonEncode(json))));
    expect(old.owner, isNull);
  });

  testWidgets('edit preferred name refreshes actual QR and permits clearing',
      (tester) async {
    final repository = OwnerWidgetRepository();
    final initial = await repository.loanInvitation('b');
    await pumpApp(
        tester,
        MaterialApp(
            debugShowCheckedModeBanner: false,
            home: LoanQrScreen(repository: repository, loan: initial)));
    expect(find.text('Właściciel: Nie podano'), findsOneWidget);
    await tester.tap(find.text('Edytuj nazwę właściciela'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '  Żaneta Łącka  ');
    await capture(tester, 'owner-input');
    await tester.tap(find.text('Zapisz i odśwież QR'));
    await tester.pumpAndSettle();
    expect(find.text('Właściciel: Żaneta Łącka'), findsOneWidget);
    await capture(tester, 'owner-qr');
    expect(find.byType(QrImageView), findsOneWidget);
    expect((await repository.loanInvitation('b')).owner, 'Żaneta Łącka');
    await tester.tap(find.text('Edytuj nazwę właściciela'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        'Żaneta Łącka');
    await tester.enterText(find.byType(TextFormField), '');
    await tester.tap(find.text('Zapisz i odśwież QR'));
    await tester.pumpAndSettle();
    expect(find.text('Właściciel: Nie podano'), findsOneWidget);
  });

  for (final name in <String?>['Jan Kowalski', null]) {
    testWidgets('preview, list and details label for $name', (tester) async {
      final repository = OwnerWidgetRepository()..name = name;
      final loan = await repository.loanInvitation('b');
      await pumpApp(
          tester,
          MaterialApp(
              debugShowCheckedModeBanner: false,
              home:
                  Scaffold(body: BorrowedLoansScreen(repository: repository))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wklej kod wypożyczenia'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), loan.encode());
      await tester.tap(find.text('Dalej'));
      await tester.pumpAndSettle();
      final label = 'Właściciel: ${name ?? 'Nie podano'}';
      expect(find.text(label), findsOneWidget);
      if (name != null) await capture(tester, 'import-preview');
      await tester.tap(find.text('Dodaj do pożyczonych'));
      await tester.pumpAndSettle();
      expect(find.textContaining(label), findsOneWidget);
      expect(find.text('Nie udało się zapisać wypożyczenia.'), findsNothing);
      if (name != null) await capture(tester, 'borrowed-list');
      await tester.ensureVisible(find.text(loan.title));
      await tester.tap(find.text(loan.title));
      await tester.pumpAndSettle();
      expect(find.text(label), findsOneWidget);
      if (name != null) await capture(tester, 'borrowed-details');
    });
  }
}
