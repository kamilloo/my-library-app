import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/data/library_database.dart';
import 'package:my_library/data/library_repository.dart';
import 'package:my_library/models/loan_transfer.dart';
import 'package:my_library/models/loan_message.dart';
import 'package:my_library/models/readable_loan.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const text =
    '${ReadableLoan.header}\n\nKsiążka: Wiedźmin\nAutor: Andrzej Sapkowski\nWłaściciel: Jan Kowalski';
// URL fixture only: no assertion that a public listing exists.
const link =
    'https://play.google.com/store/apps/details?id=com.kamilloo.mylibrary';
final today = DateTime(2026, 11, 16);
ReadableLoan parse(String s) => ReadableLoan.parse(s, today: today);
ReadableLoan entry({String title = 'Wiedźmin'}) => ReadableLoan(
    title: title,
    author: 'Andrzej Sapkowski',
    owner: 'Jan Kowalski',
    borrowedAt: today,
    isbn: '9780306406157');
LoanTransfer invitation({int revision = 1}) => LoanTransfer(
    transferId: 'transfer',
    loanId: 'loan',
    bookId: 'owned-book',
    title: 'Wiedźmin',
    author: 'Andrzej Sapkowski',
    borrowedAt: today,
    returnDate: DateTime(2026, 12, 14),
    issuedAt: today.toUtc(),
    revision: revision);

void main() {
  setUpAll(sqfliteFfiInit);
  test('Polish Unicode, optional fields, LF and CRLF', () {
    for (final s in [text, text.replaceAll('\n', '\r\n')]) {
      final loan = parse(s);
      expect(loan.title, 'Wiedźmin');
      expect(loan.owner, 'Jan Kowalski');
      expect(loan.borrowedAt, today);
      expect(loan.returnDate, isNull);
    }
    final loan = parse(
        '$text\nData wypożyczenia: 14.11.2026\nTermin zwrotu: 14.12.2026\nISBN: 9780306406157');
    expect(loan.borrowedAt, DateTime(2026, 11, 14));
    expect(loan.returnDate, DateTime(2026, 12, 14));
    expect(loan.isbn, '9780306406157');
  });
  for (final s in [
    'Cześć! $text',
    text.replaceFirst('Autor:', 'Nieznane:'),
    '$text\nAutor: Drugi',
    '$text\nTermin zwrotu: 31.02.2026',
    '$text\nISBN: 123',
    '$text\nData wypożyczenia: 2026-11-14',
    text.replaceFirst('Właściciel: Jan Kowalski', ''),
    text.replaceFirst('Książka: Wiedźmin', 'Książka: '),
    text.replaceFirst('Autor: Andrzej Sapkowski', 'Autor: '),
    '$text\nDowolna rozmowa',
    '$text\nhttps://example.com/apk',
    '$text\nTermin zwrotu: 01.01.2020',
    text.replaceFirst('Wiedźmin', List.filled(241, 'a').join()),
    List.filled(3001, 'a').join(),
  ]) {
    test('reject malformed bounded input ${s.hashCode}', () {
      expect(() => parse(s), throwsFormatException);
    });
  }
  test('configured sender link imports without recipient URL configuration',
      () {
    final message = readableInvitation(invitation(), url: link);
    expect(message, endsWith(link));
    for (final incoming in [message, message.replaceAll('\n', '\r\n')]) {
      final parsed = parse(incoming);
      expect(parsed.title, 'Wiedźmin');
      expect(parsed.author, 'Andrzej Sapkowski');
      expect(parsed.borrowedAt, today);
      expect(parsed.returnDate, DateTime(2026, 12, 14));
    }
    expect(withInstallationLink(text, url: ''), text);
    expect(
        readableInvitation(invitation(), url: ''), isNot(contains('https:')));
  });
  test('only one trailing standalone installation link is accepted', () {
    expect(parse('$text\n\n$link').title, 'Wiedźmin');
    for (final message in [
      '$text\n$link\n$link',
      '$text\n$link\nISBN: 9780306406157',
      '$text\n$link\nDalsza rozmowa',
      '$text\nZainstaluj: $link',
    ]) {
      expect(() => parse(message), throwsFormatException);
    }
  });
  for (final invalidLink in [
    link.replaceFirst('https:', 'http:'),
    link.replaceFirst('play.google.com', 'play.google.com.evil'),
    link.replaceFirst('play.google.com', 'evil.play.google.com'),
    link.replaceFirst('play.google.com', 'play-google.com'),
    link.replaceFirst('play.google.com', 'play.google.com@evil.example'),
    link.replaceFirst('play.google.com', 'user@play.google.com'),
    link.replaceFirst('play.google.com', 'play.google.com:443'),
    link.replaceFirst('/store/apps/details', '/store/apps/other'),
    link.replaceFirst(loanApplicationPackage, 'com.other.app'),
    '$link&id=$loanApplicationPackage',
    '$link&other=value',
    '$link#fragment',
    'https://example.com/apk',
  ]) {
    test('reject unrelated or malformed installation URL: $invalidLink', () {
      expect(() => parse('$text\n$invalidLink'), throwsFormatException);
      expect(withInstallationLink(text, url: invalidLink), text);
    });
  }
  for (final field in ['Książka', 'Autor', 'Właściciel']) {
    for (final embedded in [link, 'https://example.com/apk']) {
      test('reject URL embedded in $field: $embedded', () {
        final message = text.replaceFirst(
            RegExp('$field: [^\n]+'), '$field: Tekst $embedded');
        expect(() => parse(message), throwsFormatException);
      });
    }
  }
  test('all outgoing SMS are readable without encoded IDs', () {
    final loan = invitation();
    final r = LoanMessage(
        type: 'extension_request',
        requestId: 'secret-request',
        loanId: loan.loanId,
        bookId: loan.bookId,
        previousDate: loan.returnDate,
        newDate: DateTime(2027),
        revision: 1,
        timestamp: today.toUtc());
    for (final message in [
      invitationMessage(loan),
      extensionMessage(r, loan.title),
      extensionMessage(r.decision(true, today.toUtc(), 2), loan.title),
      extensionMessage(r.decision(false, today.toUtc(), 2), loan.title)
    ]) {
      expect(message, isNot(contains('moja-biblioteka:')));
      expect(message, isNot(contains('secret-request')));
      expect(message, isNot(contains('{"')));
    }
    expect(readableInvitation(loan, url: link), endsWith(link));
    expect(readableInvitation(loan, url: ''), isNot(contains('https:')));
  });

  late Directory directory;
  late String path;
  late LibraryDatabase database;
  late LibraryRepository repo;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('readable-loans');
    path = '${directory.path}/library.db';
    database = LibraryDatabase.file(databaseFactoryFfi, path);
    repo = LibraryRepository(database: database, clock: () => today);
  });
  tearDown(() async {
    await (await database.database).close();
    await directory.delete(recursive: true);
  });
  test(
      'three origins coexist, same ISBN is distinct, preview corrections survive restart',
      () async {
    await repo.importLoan(invitation());
    final manual = await repo.saveLocalBorrowed(entry(), origin: 'manual');
    await repo.saveLocalBorrowed(entry(), origin: 'manual');
    await repo.saveLocalBorrowed(entry(title: 'Poprawiony tytuł'),
        origin: 'sms', smsSource: text);
    expect((await repo.borrowedLoans()).map((l) => l.origin),
        ['qr', 'sms', 'manual', 'manual']);
    await (await database.database).close();
    database = LibraryDatabase.file(databaseFactoryFfi, path);
    repo = LibraryRepository(database: database);
    expect(
        (await repo.borrowedLoans())
            .singleWhere((l) => l.origin == 'sms')
            .title,
        'Poprawiony tytuł');
    expect(await repo.books(), isEmpty);
    await repo.deleteBorrowedLoan(manual, origin: 'manual');
    expect(await repo.borrowedLoans(), hasLength(3));
    expect((await repo.borrowedLoans()).map((l) => l.origin),
        ['qr', 'sms', 'manual']);
  });
  test(
      'duplicate exact SMS is rejected but another date and manual loan are allowed',
      () async {
    await repo.saveLocalBorrowed(entry(), origin: 'sms', smsSource: text);
    await expectLater(
        repo.saveLocalBorrowed(entry(),
            origin: 'sms', smsSource: text.replaceAll('\n', '\r\n')),
        throwsFormatException);
    await repo.saveLocalBorrowed(entry(),
        origin: 'sms', smsSource: '$text\nData wypożyczenia: 15.11.2026');
    await repo.saveLocalBorrowed(entry(), origin: 'manual');
    expect(await repo.borrowedLoans(), hasLength(3));
  });
  test('local due change never rewrites QR payload revision or owner data',
      () async {
    final qr = invitation();
    await repo.importLoan(qr);
    await repo.changeBorrowedDueDate(qr, DateTime(2027));
    final db = await database.database;
    expect((await db.query('borrowed_loans')).single['payload'], qr.encode());
    expect((await repo.borrowedLoans()).single.revision, 1);
    expect((await repo.borrowedLoans()).single.encode(), qr.encode());
    expect((await repo.borrowedLoans()).single.returnDate, DateTime(2027));
    await repo.importLoan(qr);
    await repo.importLoan(invitation(revision: 2));
    await expectLater(repo.importLoan(qr), throwsFormatException);
    expect((await repo.borrowedLoans()).single.revision, 2);
    expect((await repo.borrowedLoans()).single.transferId, qr.transferId);
    await repo.deleteBorrowedLoan(qr.loanId);
    expect(await db.query('borrowed_due_overrides'), isEmpty);
    expect(await repo.books(), isEmpty);
  });
  test('manual required fields and dates are validated at persistence boundary',
      () async {
    for (final data in [
      ReadableLoan(title: '', author: 'A', owner: 'O', borrowedAt: today),
      ReadableLoan(title: 'T', author: '', owner: 'O', borrowedAt: today),
      ReadableLoan(title: 'T', author: 'A', owner: '', borrowedAt: today),
      ReadableLoan(
          title: 'T', author: 'A', owner: 'O', borrowedAt: today, isbn: '1'),
      ReadableLoan(
          title: 'T',
          author: 'A',
          owner: 'O',
          borrowedAt: today,
          returnDate: DateTime(2020)),
    ]) {
      await expectLater(repo.saveLocalBorrowed(data, origin: 'manual'),
          throwsFormatException);
    }
    expect(await repo.borrowedLoans(), isEmpty);
  });
  test(
      'origin-aware deletion and local dates cannot touch owned books or a colliding QR id',
      () async {
    final owned = await repo.addBook(title: 'Własna książka', author: 'Autor');
    final localId = await repo.saveLocalBorrowed(entry(), origin: 'manual');
    final qr = LoanTransfer(
        transferId: 'collision',
        loanId: localId,
        bookId: owned.id,
        title: 'Wiedźmin',
        author: 'Autor',
        borrowedAt: today,
        issuedAt: today.toUtc(),
        revision: 1);
    await repo.importLoan(qr);
    await repo.saveContact('borrower', localId, '123');
    await repo.saveContact('borrower_manual', localId, '456');
    final local =
        (await repo.borrowedLoans()).singleWhere((l) => l.origin == 'manual');
    await repo.changeBorrowedDueDate(local, DateTime(2027));
    expect((await repo.books()).single.toMap(), owned.toMap());
    expect(
        (await repo.borrowedLoans())
            .singleWhere((l) => l.origin == 'qr')
            .returnDate,
        isNull);
    await repo.deleteBorrowedLoan(localId, origin: 'manual');
    expect((await repo.borrowedLoans()).single.origin, 'qr');
    expect(await repo.contact('borrower_manual', localId), isNull);
    expect(await repo.contact('borrower', localId), '123');
    expect((await repo.books()).single.toMap(), owned.toMap());
  });
  test(
      'readable owner approval uses current instance, preserves history and QR identity',
      () async {
    final book = await repo.addBook(title: 'Tytuł', author: 'Autor');
    await repo.lendBook(book, 'Anna', DateTime(2026, 12, 1));
    final qr = await repo.loanInvitation(book.id);
    await repo.approveReadableExtension(qr, DateTime(2026, 12, 21));
    final updated = await repo.loanInvitation(book.id);
    expect(updated.loanId, qr.loanId);
    expect(updated.transferId, qr.transferId);
    expect(updated.revision, qr.revision + 1);
    expect((await repo.books()).single.returnDate, DateTime(2026, 12, 21));
    expect((await repo.history()).where((e) => e.action == 'loan_extended'),
        hasLength(1));
    expect(await repo.borrowedLoans(), isEmpty);
  });
  test(
      'stale owner screen cannot approve a different loan period of the same book',
      () async {
    final book = await repo.addBook(title: 'Tytuł', author: 'Autor');
    await repo.lendBook(book, 'Anna', DateTime(2026, 12, 1));
    final old = await repo.loanInvitation(book.id);
    await repo.returnBook((await repo.books()).single);
    await repo.lendBook(
        (await repo.books()).single, 'Piotr', DateTime(2026, 12, 14));
    final current = await repo.loanInvitation(book.id);
    final history = (await repo.history()).length;
    await expectLater(repo.approveReadableExtension(old, DateTime(2027)),
        throwsFormatException);
    expect((await repo.books()).single.returnDate, DateTime(2026, 12, 14));
    expect((await repo.history()).length, history);
    expect((await repo.loanInvitation(book.id)).encode(), current.encode());
  });
  test('local records cannot be encoded as owner invitations', () async {
    await repo.saveLocalBorrowed(entry(), origin: 'manual');
    final local = (await repo.borrowedLoans()).single;
    expect(local.revision, 0);
    expect(local.transferId, isEmpty);
    expect(local.bookId, isEmpty);
    expect(local.encode, throwsStateError);
  });
}
