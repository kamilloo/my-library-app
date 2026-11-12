import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/data/library_database.dart';
import 'package:my_library/data/library_repository.dart';
import 'package:my_library/models/book.dart';
import 'package:my_library/models/loan_transfer.dart';
import 'package:my_library/models/loan_message.dart';
import 'package:my_library/services/cover_storage.dart';
import 'package:my_library/services/return_reminders.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'return_reminders_test.dart' show FakeNotifications;

class RecordingCoverStorage extends CoverStorage {
  final deleted = <String?>[];
  @override
  Future<void> delete(String? reference) async {
    deleted.add(reference);
  }
}

void main() {
  late LibraryDatabase database;
  late Database db;
  late LibraryRepository repository;
  late ReturnReminders reminders;
  late FakeNotifications notifications;
  late RecordingCoverStorage covers;
  final now = DateTime(2026, 11, 12, 12);

  setUpAll(() {
    sqfliteFfiInit();
    tzdata.initializeTimeZones();
  });
  setUp(() async {
    database = LibraryDatabase.inMemory(databaseFactoryFfi);
    db = await database.database;
    covers = RecordingCoverStorage();
    notifications = FakeNotifications();
    reminders = ReturnReminders(database, notifications, now: () => now);
    repository = LibraryRepository(
        database: database,
        coverStorage: covers,
        reminders: reminders,
        clock: () => now);
  });
  tearDown(() async => db.close());

  Future<Book> currentBook(String id) async =>
      (await repository.books()).singleWhere((b) => b.id == id);

  Future<LoanTransfer> exportAndMessage(String bookId) async {
    final loan = await repository.loanInvitation(bookId);
    await repository.importLoan(loan);
    final request =
        await repository.prepareExtension(loan.loanId, DateTime(2026, 12, 27));
    await repository.markRequestSent(request.requestId);
    await repository.decideExtension(request, true);
    await repository.saveContact('owner', loan.loanId, '+48 123456789');
    await repository.saveContact('borrower', loan.loanId, '+48 987654321');
    return loan;
  }

  Future<LoanTransfer> seedLoan({bool legacy = false}) async {
    final book = await repository.addBook(
        title: 'Żółć', author: 'Łukasz', coverUrl: 'covers/original.jpg');
    await repository.lendBook(book, 'Anna', DateTime(2026, 12, 20));
    if (legacy) {
      // Task 19 assigns an independent ID to already-borrowed legacy records.
      await db.delete('owner_loan_instances',
          where: 'book_id = ?', whereArgs: [book.id]);
    }
    return exportAndMessage(book.id);
  }

  Future<List<Map<String, Object?>>> roleRows(
          String table, String role, String loanId) =>
      db.query(table,
          where: 'role = ? AND loan_id = ?', whereArgs: [role, loanId]);

  Future<Map<String, List<Map<String, Object?>>>> snapshot() async => {
        for (final table in [
          'books',
          'history',
          'owner_loan_instances',
          'loan_transfers',
          'borrowed_loans',
          'loan_messages',
          'loan_contacts',
          'return_reminders'
        ])
          table: await db.query(table, orderBy: 'rowid'),
      };

  test(
      'borrower deletion clears personal data and preserves owner role and unrelated loans',
      () async {
    final loan = await seedLoan();
    final unrelated = await seedLoan();
    final before = await snapshot();
    final otherMessages =
        await repository.messages('borrower', loanId: unrelated.loanId);
    final ownerMessages = await repository.messages('owner');
    final ownerContacts =
        await db.query('loan_contacts', where: "role = 'owner'");

    await repository.deleteBorrowedLoan(loan.loanId);

    expect((await repository.borrowedLoans()).map((l) => l.loanId),
        [unrelated.loanId]);
    expect(await roleRows('loan_messages', 'borrower', loan.loanId), isEmpty);
    expect(await repository.contact('borrower', loan.loanId), isNull);
    expect(await repository.messages('borrower', loanId: unrelated.loanId),
        otherMessages);
    expect(await repository.contact('borrower', unrelated.loanId),
        '+48 987654321');
    expect(await repository.messages('owner'), ownerMessages);
    expect(await db.query('loan_contacts', where: "role = 'owner'"),
        ownerContacts);
    for (final table in [
      'books',
      'history',
      'owner_loan_instances',
      'loan_transfers',
      'return_reminders'
    ]) {
      expect(await db.query(table, orderBy: 'rowid'), before[table],
          reason: table);
    }
    expect(covers.deleted, isEmpty);
  });

  test(
      'reimport after deletion starts without obsolete requests, decisions or phone',
      () async {
    final loan = await seedLoan();
    final oldRequestId =
        (await repository.messages('borrower')).single['request_id'];
    final decision =
        (await repository.messages('owner')).single['decision']! as String;
    // Cover the imported-confirmation tombstone as well as a pending request.
    final ownerRows = await repository.messages('owner');
    expect(ownerRows.single['state'], 'approved');
    await repository.importConfirmation(LoanMessage.decode(decision));
    await repository.deleteBorrowedLoan(loan.loanId);
    await repository.importLoan(LoanTransfer.decode(loan.encode()));
    await repository.importLoan(loan); // Task 19 duplicate imports remain safe.
    expect(await repository.messages('borrower', loanId: loan.loanId), isEmpty);
    expect(await repository.contact('borrower', loan.loanId), isNull);
    expect((await repository.borrowedLoans()).single.encode(), loan.encode());
    final fresh =
        await repository.prepareExtension(loan.loanId, DateTime(2027));
    expect(fresh.requestId, isNot(oldRequestId));
    expect((await repository.messages('borrower')).single['state'], 'prepared');
    expect(await repository.messages('owner'), ownerRows);
  });

  test('return and re-lending retain messages, contacts and old snapshots',
      () async {
    final loan = await seedLoan(legacy: true);
    final messages = await db.query('loan_messages');
    final contacts = await db.query('loan_contacts');
    final transfers = await db.query('loan_transfers');

    await repository.returnBook(await currentBook(loan.bookId));
    expect(await db.query('owner_loan_instances'), isEmpty);
    expect(await db.query('loan_messages'), messages);
    expect(await db.query('loan_contacts'), contacts);
    expect(await db.query('loan_transfers'), transfers);

    await repository.lendBook(
        await currentBook(loan.bookId), 'Ola', DateTime(2027));
    final next = await repository.loanInvitation(loan.bookId);
    expect(next.loanId, isNot(loan.loanId));
    expect(await db.query('loan_messages'), messages);
    expect(await db.query('loan_contacts'), contacts);
    expect(
        (await db.query('loan_transfers'))
            .where((r) => r['loan_id'] == loan.loanId)
            .single,
        transfers.single);
    expect(covers.deleted, isEmpty);
  });

  test(
      'owner deletion cleans legacy, returned contact-only and active instances while preserving borrower role',
      () async {
    final legacy = await seedLoan(legacy: true);
    final legacyEvent = (await db.query('history',
            where: "book_id = ? AND action = 'borrowed'",
            whereArgs: [legacy.bookId]))
        .single['id'];
    expect(legacy.loanId, isNot(legacyEvent));
    await repository.returnBook(await currentBook(legacy.bookId));

    // A returned instance may have a saved contact but no transfer snapshot.
    await repository.lendBook(
        await currentBook(legacy.bookId), 'Ola', DateTime(2027));
    final contactOnly = (await db.query('owner_loan_instances',
            where: 'book_id = ?', whereArgs: [legacy.bookId]))
        .single['loan_id']! as String;
    await repository.saveContact('owner', contactOnly, '111222333');
    await repository.returnBook(await currentBook(legacy.bookId));
    await repository.lendBook(
        await currentBook(legacy.bookId), 'Jan', DateTime(2026, 12, 20));
    final active = await exportAndMessage(legacy.bookId);
    final unrelated = await seedLoan();

    final borrowerMessages = await repository.messages('borrower');
    final borrowerContacts =
        await db.query('loan_contacts', where: "role = 'borrower'");
    final borrowed = await db.query('borrowed_loans');
    final unrelatedMessages =
        await repository.messages('owner', loanId: unrelated.loanId);
    final unrelatedTransfers = await db.query('loan_transfers',
        where: 'loan_id = ?', whereArgs: [unrelated.loanId]);
    await reminders.setEnabled(legacy.bookId, true);
    final reminderId = (await db.query('return_reminders',
            where: 'book_id = ?', whereArgs: [legacy.bookId]))
        .single['id']! as int;

    await repository.deleteBook(legacy.bookId);

    expect((await repository.books()).map((b) => b.id), [unrelated.bookId]);
    for (final id in [legacy.loanId, contactOnly, active.loanId]) {
      expect(await roleRows('loan_messages', 'owner', id), isEmpty);
      expect(await repository.contact('owner', id), isNull);
      expect(
          await db
              .query('loan_transfers', where: 'loan_id = ?', whereArgs: [id]),
          isEmpty);
    }
    expect(
        await db.query('owner_loan_instances',
            where: 'book_id = ?', whereArgs: [legacy.bookId]),
        isEmpty);
    expect(
        await db
            .query('history', where: 'book_id = ?', whereArgs: [legacy.bookId]),
        isEmpty);
    expect(await repository.messages('owner', loanId: unrelated.loanId),
        unrelatedMessages);
    expect(
        await repository.contact('owner', unrelated.loanId), '+48 123456789');
    expect(
        await db.query('loan_transfers',
            where: 'loan_id = ?', whereArgs: [unrelated.loanId]),
        unrelatedTransfers);
    expect(await repository.messages('borrower'), borrowerMessages);
    expect(await db.query('loan_contacts', where: "role = 'borrower'"),
        borrowerContacts);
    expect(await db.query('borrowed_loans'), borrowed);
    expect(await reminders.enabled(legacy.bookId), isFalse);
    expect(notifications.cancellations, contains(reminderId));
    expect(notifications.pending, isNot(contains(reminderId)));
    // The unrelated book still shares the cover, so it must not be removed.
    expect(covers.deleted, isEmpty);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test(
      'deleting a returned legacy book with no active mapping cleans its personal data',
      () async {
    final loan = await seedLoan(legacy: true);
    await repository.returnBook(await currentBook(loan.bookId));
    expect(await db.query('owner_loan_instances'), isEmpty);
    await repository.deleteBook(loan.bookId);
    expect(await repository.messages('owner'), isEmpty);
    expect(await repository.contact('owner', loan.loanId), isNull);
    expect(await db.query('loan_transfers'), isEmpty);
    expect(await repository.messages('borrower'), hasLength(1));
    expect(covers.deleted, ['covers/original.jpg']);
  });

  for (final role in ['borrower', 'owner']) {
    for (final table in [
      'loan_messages',
      'loan_contacts',
      if (role == 'owner') 'loan_transfers'
    ]) {
      test('$role deletion rolls back every record on failed $table cleanup',
          () async {
        final loan = await seedLoan(legacy: true);
        await reminders.setEnabled(loan.bookId, true);
        final before = await snapshot();
        final pending = Map.of(notifications.pending);
        final cancellations = List.of(notifications.cancellations);
        await db.execute(
            "CREATE TRIGGER fail_cleanup BEFORE DELETE ON $table BEGIN SELECT RAISE(ABORT, 'cleanup failure'); END");

        await expectLater(
            role == 'owner'
                ? repository.deleteBook(loan.bookId)
                : repository.deleteBorrowedLoan(loan.loanId),
            throwsA(isA<DatabaseException>()));

        expect(await snapshot(), before);
        expect(notifications.pending, pending);
        expect(notifications.cancellations, cancellations);
        expect(covers.deleted, isEmpty);
        await db.execute('DROP TRIGGER fail_cleanup');
        if (role == 'owner') {
          await repository.deleteBook(loan.bookId);
          expect(covers.deleted, ['covers/original.jpg']);
          expect(await reminders.enabled(loan.bookId), isFalse);
        } else {
          await repository.deleteBorrowedLoan(loan.loanId);
          expect(await repository.borrowedLoans(), isEmpty);
        }
      });
    }
  }
}
