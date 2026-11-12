import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/data/library_database.dart';
import 'package:my_library/data/library_repository.dart';
import 'package:my_library/models/book.dart';
import 'package:my_library/models/loan_message.dart';
import 'package:my_library/models/loan_transfer.dart';
import 'package:my_library/models/return_date.dart';
import 'package:my_library/screens/loan_extension_dialog.dart';
import 'package:my_library/screens/loan_messaging.dart';
import 'package:my_library/services/loan_sms.dart';
import 'package:my_library/services/return_reminders.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'return_reminders_test.dart' show FakeNotifications;
import 'fixtures/legacy_library_schema.dart';

String rawMessage(Map<String, Object?> map) =>
    LoanTransfer.prefix + base64Url.encode(utf8.encode(jsonEncode(map)));

class MessageWidgetRepository extends LibraryRepository {
  MessageWidgetRepository(this.loan, this.book);
  final LoanTransfer loan;
  final Book book;
  int decisions = 0, imports = 0;
  @override
  Future<List<Map<String, Object?>>> messages(String role,
          {String? loanId}) async =>
      [];
  @override
  Future<Book> previewExtension(LoanMessage request) async => book;
  @override
  Future<LoanMessage> decideExtension(
      LoanMessage request, bool approved) async {
    decisions++;
    return request.decision(approved, DateTime(2026, 11, 12, 12), 2);
  }

  @override
  Future<LoanTransfer> previewConfirmation(LoanMessage message) async => loan;
  @override
  Future<void> importConfirmation(LoanMessage message) async {
    imports++;
  }

  @override
  Future<List<LoanTransfer>> borrowedLoans() async => [loan];
  @override
  Future<String?> contact(String role, String loanId) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    tzdata.initializeTimeZones();
  });
  final now = DateTime(2026, 11, 12, 12);
  late LibraryDatabase ownerDb, borrowerDb;
  late Directory stores;
  late LibraryRepository owner, borrower;
  late ReturnReminders reminders;
  late FakeNotifications notifications;
  late LoanTransfer loan;
  late Book book;

  setUp(() async {
    stores = await Directory.systemTemp.createTemp('loan-messaging');
    ownerDb =
        LibraryDatabase.file(databaseFactoryFfi, '${stores.path}/owner.db');
    borrowerDb =
        LibraryDatabase.file(databaseFactoryFfi, '${stores.path}/borrower.db');
    notifications = FakeNotifications();
    reminders = ReturnReminders(ownerDb, notifications, now: () => now);
    owner = LibraryRepository(
        database: ownerDb, clock: () => now, reminders: reminders);
    borrower = LibraryRepository(database: borrowerDb, clock: () => now);
    book = await owner.addBook(title: 'Wiedźmin: Żółć', author: 'Łukasz Ćma');
    await owner.lendBook(book, 'Małgorzata', DateTime(2026, 12, 20));
    book = (await owner.books()).single;
    loan = await owner.loanInvitation(book.id);
    await borrower.importLoan(loan);
  });
  tearDown(() async {
    await (await ownerDb.database).close();
    await (await borrowerDb.database).close();
    await stores.delete(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LoanSms.channel, null);
  });

  Future<LoanMessage> request() =>
      borrower.prepareExtension(loan.loanId, DateTime(2026, 12, 27));

  test('invitation preserves exact v1 QR code and readable Polish text', () {
    final text = invitationMessage(loan);
    expect(text, contains('Wiedźmin: Żółć'));
    expect(text, contains('20.12.2026'));
    expect(text, contains('Po instalacji wklej'));
    expect(text, isNot(contains('play.google.com')));
    expect(
        LoanTransfer.decode(text.split('\n\n').last).encode(), loan.encode());
    expect(text, isNot(contains('Małgorzata')));
  });

  test('request roundtrip, decision types and compact bounded envelope',
      () async {
    final r = await request();
    expect(LoanMessage.decode(r.encode()).encode(), r.encode());
    expect(r.encode().length, lessThan(1000));
    for (final approved in [true, false]) {
      final d = r.decision(approved, now, 2);
      expect(LoanMessage.decode(d.encode()).encode(), d.encode());
      expect(extensionMessage(d, loan.title), contains('Wiedźmin: Żółć'));
    }
    expect(extensionMessage(r, loan.title), contains('nie zmienia terminu'));
    expect((await borrower.borrowedLoans()).single.returnDate, loan.returnDate);
    expect((await borrower.messages('borrower')).single['state'], 'prepared');
    await borrower.markRequestSent(r.requestId);
    expect((await borrower.messages('borrower')).single['state'], 'pending');
  });

  for (final entry in <String, Object?>{
    'v': 2,
    'p': 'other',
    't': 'unknown',
    'id': '',
    'loan': null,
    'book': List.filled(81, 'a').join(),
    'revision': 0,
    'due': '2026-02-30',
    'new_due': '2026-12-20',
    'issued': 'yesterday',
  }.entries) {
    test('malformed ${entry.key} rejects without database mutations', () async {
      final r = await request();
      final before = await (await borrowerDb.database).query('borrowed_loans');
      expect(
          () => LoanMessage.decode(
              rawMessage({...r.toJson(), entry.key: entry.value})),
          throwsFormatException);
      expect(await (await borrowerDb.database).query('borrowed_loans'), before);
    });
  }
  test('oversized, invalid UTF8/base64, control chars and fractional version',
      () async {
    final r = await request();
    for (final code in [
      'bad',
      'moja-biblioteka:***',
      'a' * 2401,
      rawMessage({...r.toJson(), 'id': 'bad\n'}),
      rawMessage({...r.toJson(), 'v': 1.0}),
      rawMessage({...r.toJson(), 'issued': '2026-11-12T25:00:00.000Z'}),
      rawMessage({...r.toJson(), 'new_due': '2026-13-01'}),
      rawMessage({...r.toJson(), 't': 'extension_approved', 'new_revision': 1}),
    ]) {
      expect(() => LoanMessage.decode(code), throwsFormatException);
    }
  });

  test(
      'parsing and preview are read-only; approval preserves metadata and opt-in',
      () async {
    await reminders.setEnabled(book.id, true);
    final reminderRows =
        await (await ownerDb.database).query('return_reminders');
    final r = LoanMessage.decode((await request()).encode());
    final db = await ownerDb.database;
    final before = await db.query('books');
    final history = await db.query('history');
    await owner.previewExtension(r);
    expect(await db.query('books'), before);
    expect(await db.query('history'), history);
    expect(await owner.messages('owner'), isEmpty);
    final d = await owner.decideExtension(r, true);
    expect(d.type, 'extension_approved');
    expect(d.newRevision, greaterThan(r.revision));
    final after = (await db.query('books')).single;
    for (final key in before.single.keys
        .where((k) => k != 'return_date' && k != 'updated_at')) {
      expect(after[key], before.single[key], reason: key);
    }
    expect(await db.query('return_reminders'), reminderRows);
    expect(notifications.pending.values.single.day, 27);
    expect(await db.query('history', where: "action = 'loan_extended'"),
        hasLength(1));
    expect(await db.query('history', where: "action = 'return_date_changed'"),
        isEmpty);
    await expectLater(owner.decideExtension(r, true), throwsFormatException);
    await expectLater(owner.decideExtension(r, false), throwsFormatException);
    final saved = (await owner.messages('owner')).single;
    expect(
        LoanMessage.decode(saved['decision']! as String).encode(), d.encode());
    expect(await db.query('history', where: "action = 'loan_extended'"),
        hasLength(1));
  });

  test(
      'rejection has no loan, history or reminder side effects and cannot approve again',
      () async {
    await reminders.setEnabled(book.id, true);
    final db = await ownerDb.database;
    final before = await db.query('books');
    final history = await db.query('history');
    final pending = Map.of(notifications.pending);
    final r = await request();
    final d = await owner.decideExtension(r, false);
    expect(d.type, 'extension_rejected');
    expect(await db.query('books'), before);
    expect(await db.query('history'), history);
    expect(notifications.pending, pending);
    expect((await owner.messages('owner')).single['state'], 'rejected');
    await expectLater(owner.decideExtension(r, true), throwsFormatException);
  });

  test('stale term, revision and loan-instance IDs reject', () async {
    final r = await request();
    for (final map in [
      {...r.toJson(), 'loan': 'other'},
      {...r.toJson(), 'book': 'other'},
      {...r.toJson(), 'revision': 3},
      {...r.toJson(), 'due': '2026-12-19'},
    ]) {
      await expectLater(
          owner.previewExtension(LoanMessage.decode(rawMessage(map))),
          throwsFormatException);
    }
    await owner.previewExtension(r);
    await owner.updateReturnDate(book.id, DateTime(2026, 12, 21));
    await expectLater(owner.decideExtension(r, true), throwsFormatException);
    // Even returning to the same date must not revive an obsolete revision.
    await owner.updateReturnDate(book.id, DateTime(2026, 12, 20));
    await expectLater(owner.decideExtension(r, true), throwsFormatException);
    await owner.returnBook((await owner.books()).single);
    await owner.lendBook((await owner.books()).single, 'Anna', loan.returnDate);
    await expectLater(owner.decideExtension(r, true), throwsFormatException);
  });

  test('deletion and returned owner record reject approval', () async {
    final r = await request();
    await owner.deleteBook(book.id);
    await expectLater(owner.previewExtension(r), throwsFormatException);
    await expectLater(owner.decideExtension(r, true),
        throwsA(anyOf(isA<FormatException>(), isA<ReturnDateException>())));
  });

  test(
      'duplicate request ID with changed content cannot create second decision',
      () async {
    final r = await request();
    await owner.decideExtension(r, false);
    final conflict = LoanMessage.decode(
        rawMessage({...r.toJson(), 'new_due': '2027-01-01'}));
    await expectLater(
        owner.decideExtension(conflict, true), throwsFormatException);
    expect(await owner.messages('owner'), hasLength(1));
  });

  test(
      'decision insert failure rolls back date, revision, history and reminders',
      () async {
    final r = await request();
    await reminders.setEnabled(book.id, true);
    final db = await ownerDb.database;
    final before = await db.query('books');
    final transfers = await db.query('loan_transfers');
    final history = await db.query('history');
    final pending = Map.of(notifications.pending);
    await db.execute(
        "CREATE TRIGGER fail_decision BEFORE INSERT ON loan_messages BEGIN SELECT RAISE(ABORT, 'test'); END");
    await expectLater(
        owner.decideExtension(r, true), throwsA(isA<DatabaseException>()));
    expect(await db.query('books'), before);
    expect(await db.query('history'), history);
    expect(await db.query('loan_transfers'), transfers);
    expect(notifications.pending, pending);
    expect(await db.query('loan_messages'), isEmpty);
  });

  test('concurrent approvals and canceled or failed SMS never extend twice',
      () async {
    final r = await request();
    final results = await Future.wait([
      for (var i = 0; i < 2; i++)
        owner
            .decideExtension(r, true)
            .then<Object>((value) => value, onError: (Object e) => e),
    ]);
    expect(results.whereType<LoanMessage>(), hasLength(1));
    final decision = results.whereType<LoanMessage>().single;
    for (final failure in [false, true]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(LoanSms.channel, (_) async {
        if (failure) throw PlatformException(code: 'unavailable');
        return null; // Composer opened then canceled; no delivery callback.
      });
      await const LoanSms().compose(extensionMessage(decision, loan.title), '');
      expect((await owner.books()).single.returnDate, decision.newDate);
      expect((await owner.messages('owner')).single['decision'],
          decision.encode());
    }
    expect(
        await (await ownerDb.database)
            .query('history', where: "action = 'loan_extended'"),
        hasLength(1));
  });

  test('borrower confirmation is explicit, transactional and duplicate-safe',
      () async {
    final r = await request();
    final d = await owner.decideExtension(r, true);
    final before = (await borrower.borrowedLoans()).single.encode();
    await borrower.previewConfirmation(LoanMessage.decode(d.encode()));
    expect((await borrower.borrowedLoans()).single.encode(), before);
    await borrower.importConfirmation(d);
    final after = (await borrower.borrowedLoans()).single;
    expect(after.returnDate, d.newDate);
    expect(after.revision, d.newRevision);
    expect(after.bookId, loan.bookId);
    expect(after.borrowedAt, loan.borrowedAt);
    expect((await borrower.messages('borrower')).single['state'], 'imported');
    await borrower.importConfirmation(d);
    expect((await borrower.borrowedLoans()).single.encode(), after.encode());
    expect(await borrower.history(), isEmpty);
    expect(await borrower.books(), isEmpty);
    final next =
        await borrower.prepareExtension(loan.loanId, DateTime(2027, 1, 5));
    final second = await owner.decideExtension(next, true);
    await borrower.importConfirmation(second);
    await borrower.importConfirmation(d);
    expect((await borrower.borrowedLoans()).single.returnDate, second.newDate);
    await expectLater(
        borrower.importConfirmation(LoanMessage.decode(
            rawMessage({...d.toJson(), 'id': 'unknown-old'}))),
        throwsFormatException);
  });

  test(
      'confirmation conflicts and another borrowing period never update wrong row',
      () async {
    final r = await request();
    final d = await owner.decideExtension(r, true);
    for (final map in [
      {...d.toJson(), 'loan': 'wrong'},
      {...d.toJson(), 'book': 'wrong'},
      {...d.toJson(), 'revision': 4, 'new_revision': 5},
      {...d.toJson(), 'due': '2026-12-19'},
      {...d.toJson(), 'new_due': '2027-01-01'},
      {...d.toJson(), 'issued': '2026-11-11T12:00:00.000Z'},
    ]) {
      await expectLater(
          borrower.importConfirmation(LoanMessage.decode(rawMessage(map))),
          throwsFormatException);
    }
    expect((await borrower.borrowedLoans()).single.encode(), loan.encode());
    await borrower.importConfirmation(d);
    await expectLater(
        borrower.importConfirmation(LoanMessage.decode(
            rawMessage({...d.toJson(), 'new_due': '2027-01-01'}))),
        throwsFormatException);
  });

  test(
      'confirmation can be accepted without local request but cannot accept rejection',
      () async {
    final r = await request();
    final d = await owner.decideExtension(r, true);
    await (await borrowerDb.database).delete('loan_messages');
    await borrower.importConfirmation(d);
    expect((await borrower.borrowedLoans()).single.returnDate, d.newDate);
    await expectLater(borrower.importConfirmation(r.decision(false, now, 1)),
        throwsFormatException);
  });

  test('confirmation decision write failure rolls back local date', () async {
    final d = await owner.decideExtension(await request(), true);
    final db = await borrowerDb.database;
    await db.execute(
        "CREATE TRIGGER fail_import BEFORE UPDATE ON loan_messages BEGIN SELECT RAISE(ABORT, 'test'); END");
    await expectLater(
        borrower.importConfirmation(d), throwsA(isA<DatabaseException>()));
    expect((await borrower.borrowedLoans()).single.encode(), loan.encode());
    expect((await borrower.messages('borrower')).single['state'], 'prepared');
  });

  test('presets and invalid overdue proposals are checked in repository',
      () async {
    for (final days in [7, 14, 30]) {
      final date = extendedReturnDate(loan.returnDate!, days);
      final r = await borrower.prepareExtension(loan.loanId, date);
      expect(r.newDate, date);
    }
    for (final date in [
      loan.returnDate!,
      DateTime(2026, 11, 12),
      DateTime(2026, 11, 1)
    ]) {
      await expectLater(
          borrower.prepareExtension(loan.loanId, date), throwsFormatException);
    }
  });

  test('optional contact is local, explicit, removable and absent from exports',
      () async {
    expect(await owner.contact('owner', loan.loanId), isNull);
    await owner.saveContact('owner', loan.loanId, '+48 123 456 789');
    expect(await owner.contact('owner', loan.loanId), '+48 123 456 789');
    expect(await borrower.contact('owner', loan.loanId), isNull);
    expect(invitationMessage(await owner.loanInvitation(book.id)),
        isNot(contains('+48')));
    await expectLater(
        owner.saveContact('owner', loan.loanId, 'sms:evil?body=x'),
        throwsFormatException);
    await owner.saveContact('owner', loan.loanId, '');
    expect(await owner.contact('owner', loan.loanId), isNull);
  });

  test('SMS adapter requests composer with Unicode body and optional recipient',
      () async {
    MethodCall? call;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LoanSms.channel, (c) async {
      call = c;
      return null;
    });
    final text = invitationMessage(loan);
    expect(await const LoanSms().compose(text, '+48 123456789'), isTrue);
    expect(call!.method, 'sms');
    expect(call!.arguments, {'text': text, 'phone': '+48 123456789'});
    expect((await owner.books()).single.returnDate, loan.returnDate);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LoanSms.channel,
            (_) async => throw PlatformException(code: 'unavailable'));
    expect(await const LoanSms().compose(text, ''), isFalse);
    expect(await const LoanSms().share(text), isFalse);
  });

  testWidgets(
      'missing SMS app exposes copy and share; composer does not mark sent',
      (tester) async {
    var recorded = 0;
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LoanSms.channel,
            (_) async => throw PlatformException(code: 'unavailable'));
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(MaterialApp(
        home: SmsMessageScreen(
            text: 'Żółć',
            onSent: () async {
              recorded++;
            })));
    await tester.tap(find.text('Otwórz aplikację SMS'));
    await tester.pumpAndSettle();
    expect(recorded, 0);
    expect(find.textContaining('Nie udało się otworzyć'), findsOneWidget);
    await tester.tap(find.text('Kopiuj wiadomość'));
    await tester.pumpAndSettle();
    expect(copied, 'Żółć');
    await tester.ensureVisible(find.text('Zapisz, że wysłano prośbę'));
    await tester.tap(find.text('Zapisz, że wysłano prośbę'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anuluj'));
    await tester.pumpAndSettle();
    expect(recorded, 0);
    await tester.tap(find.text('Zapisz, że wysłano prośbę'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tak, wysłałem prośbę'));
    await tester.pumpAndSettle();
    expect(recorded, 1);
  });

  testWidgets('request UI shows preset date without extending actual record',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (c) => TextButton(
                    onPressed: () => showDialog<LoanMessage>(
                        context: c,
                        builder: (_) => LoanExtensionDialog(
                            book: book,
                            repository: borrower,
                            requestLoanId: loan.loanId)),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Prośba nie przedłuża'), findsOneWidget);
    await tester.tap(find.text('+7 dni'));
    await tester.pumpAndSettle();
    expect(find.text('Nowy termin zwrotu: 27.12.2026'), findsOneWidget);
    await tester.tap(find.text('Przygotuj prośbę SMS'));
    await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      expect(
          (await borrower.borrowedLoans()).single.returnDate, loan.returnDate);
      expect(await borrower.messages('borrower'), hasLength(1));
    });
  });

  testWidgets(
      'missing stored date disables presets and requires custom future date',
      (tester) async {
    await tester.runAsync(() async {
      await owner.updateReturnDate(book.id, null);
      loan = await owner.loanInvitation(book.id);
      await borrower.importLoan(loan);
      book = (await owner.books()).single;
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: LoanExtensionDialog(
                book: book,
                repository: borrower,
                requestLoanId: loan.loanId))));
    expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '+7 dni'))
            .onSelected,
        isNull);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Przygotuj prośbę SMS'))
            .onPressed,
        isNull);
    await tester.tap(find.text('Wybierz datę'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wybierz'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nowy termin zwrotu:'), findsOneWidget);
    await tester.runAsync(() async {
      final r =
          await borrower.prepareExtension(loan.loanId, DateTime(2026, 11, 13));
      expect(r.previousDate, isNull);
      await owner.decideExtension(r, true);
    });
  });

  for (final approve in [true, false]) {
    testWidgets(
        'owner request preview cancellation is read-only then decision: $approve',
        (tester) async {
      final repo = MessageWidgetRepository(loan, book);
      final r = LoanMessage(
          type: 'extension_request',
          requestId: 'ui-request',
          loanId: loan.loanId,
          bookId: loan.bookId,
          previousDate: loan.returnDate,
          newDate: DateTime(2026, 12, 27),
          revision: 1,
          timestamp: now);
      await tester.pumpWidget(MaterialApp(
          home: LoanMessagingScreen(
              repository: repo, loan: loan, ownerSide: true)));
      await tester.pumpAndSettle();
      Future<void> preview() async {
        await tester.tap(find.text('Odczytaj prośbę o przedłużenie'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), r.encode());
        await tester.tap(find.text('Dalej'));
        await tester.pumpAndSettle();
      }

      await preview();
      expect(find.text('Niezweryfikowana prośba'), findsOneWidget);
      expect(repo.decisions, 0);
      await tester.tap(find.text('Anuluj'));
      await tester.pumpAndSettle();
      expect(repo.decisions, 0);
      await preview();
      await tester
          .tap(find.text(approve ? 'Zatwierdź przedłużenie' : 'Odrzuć prośbę'));
      await tester.pumpAndSettle();
      expect(repo.decisions, 1);
      expect(find.text('Przygotowana wiadomość'), findsOneWidget);
      // No native composer is launched until the explicit button is pressed.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(repo.decisions, 1);
    });
  }

  testWidgets('borrower confirmation preview requires explicit apply',
      (tester) async {
    final repo = MessageWidgetRepository(loan, book);
    final message = LoanMessage(
        type: 'extension_approved',
        requestId: 'ui-confirmation',
        loanId: loan.loanId,
        bookId: loan.bookId,
        previousDate: loan.returnDate,
        newDate: DateTime(2026, 12, 27),
        revision: 1,
        newRevision: 2,
        timestamp: now);
    await tester.pumpWidget(MaterialApp(
        home: LoanMessagingScreen(
            repository: repo, loan: loan, ownerSide: false)));
    await tester.pumpAndSettle();
    Future<void> preview() async {
      await tester.tap(find.text('Wklej potwierdzenie przedłużenia'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), message.encode());
      await tester.tap(find.text('Dalej'));
      await tester.pumpAndSettle();
    }

    await preview();
    expect(find.text('Niezweryfikowane potwierdzenie'), findsOneWidget);
    expect(repo.imports, 0);
    await tester.tap(find.text('Anuluj'));
    await tester.pumpAndSettle();
    expect(repo.imports, 0);
    await preview();
    await tester.tap(find.text('Zastosuj nowy termin'));
    await tester.pumpAndSettle();
    expect(repo.imports, 1);
  });

  test(
      'Android composer and permission audit exclude automatic SMS and contacts access',
      () async {
    final native = await File(
            'android/app/src/main/kotlin/com/kamilloo/mylibrary/MainActivity.kt')
        .readAsString();
    expect(native, contains('Intent.ACTION_SENDTO'));
    expect(native, contains('Uri.fromParts("smsto", phone, null)'));
    expect(native, contains('putExtra("sms_body", text)'));
    expect(native, isNot(contains('SmsManager')));
    for (final variant in ['main', 'debug', 'profile']) {
      final manifest =
          await File('android/app/src/$variant/AndroidManifest.xml')
              .readAsString();
      for (final permission in [
        'SEND_SMS',
        'READ_SMS',
        'RECEIVE_SMS',
        'READ_CONTACTS',
        'WRITE_CONTACTS'
      ]) {
        expect(manifest, isNot(contains('android.permission.$permission')));
      }
    }
    final pubspec = await File('pubspec.yaml').readAsString();
    expect(pubspec.toLowerCase(), isNot(contains('firebase')));
  });

  test(
      'v4 upgrade and restart preserve contacts, pending requests and imported decisions',
      () async {
    final dir = await Directory.systemTemp.createTemp('messages-migration');
    final path = '${dir.path}/library.db';
    final v4 = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
            version: 4,
            onCreate: (db, _) async {
              await createLegacySchema(db, 3);
              await db.execute(
                  'CREATE TABLE owner_loan_instances (book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE, loan_id TEXT NOT NULL UNIQUE)');
              await db.execute(
                  'CREATE TABLE loan_transfers (loan_id TEXT PRIMARY KEY, payload TEXT NOT NULL)');
              await db.execute(
                  "CREATE TABLE borrowed_loans (loan_id TEXT PRIMARY KEY, transfer_id TEXT NOT NULL UNIQUE, payload TEXT NOT NULL, revision INTEGER NOT NULL, local_status TEXT NOT NULL DEFAULT 'active')");
            }));
    await v4.insert('books', book.toMap());
    await v4.insert('return_reminders', {'book_id': book.id, 'enabled': 1});
    await v4.insert('borrowed_loans', {
      'loan_id': loan.loanId,
      'transfer_id': loan.transferId,
      'payload': loan.encode(),
      'revision': 1
    });
    final oldBooks = await v4.query('books');
    final oldBorrowed = await v4.query('borrowed_loans');
    final oldReminders = await v4.query('return_reminders');
    await v4.close();
    var db = LibraryDatabase.file(databaseFactoryFfi, path);
    var repo = LibraryRepository(database: db, clock: () => now);
    final sqlite = await db.database;
    expect(await sqlite.getVersion(), 5);
    expect(await sqlite.query('books'), oldBooks);
    expect(await sqlite.query('borrowed_loans'), oldBorrowed);
    expect(await sqlite.query('return_reminders'), oldReminders);
    final pending = await repo.prepareExtension(loan.loanId, DateTime(2027));
    final r = await repo.prepareExtension(loan.loanId, DateTime(2026, 12, 27));
    final d = await owner.decideExtension(r, true);
    await repo.importConfirmation(d);
    await repo.saveContact('borrower', loan.loanId, '123456789');
    await sqlite.close();
    db = LibraryDatabase.file(databaseFactoryFfi, path);
    repo = LibraryRepository(database: db, clock: () => now);
    expect(await repo.contact('borrower', loan.loanId), '123456789');
    expect((await repo.messages('borrower')).map((r) => r['state']),
        containsAll(['prepared', 'imported']));
    expect(
        (await repo.messages('borrower'))
            .any((r) => r['request_id'] == pending.requestId),
        isTrue);
    await repo.importConfirmation(d);
    expect((await repo.borrowedLoans()).single.returnDate, d.newDate);
    expect(await (await db.database).rawQuery('PRAGMA foreign_key_check'),
        isEmpty);
    await (await db.database).close();
    await dir.delete(recursive: true);
  });
}
