import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/book.dart';
import '../models/loan_transfer.dart';
import '../models/loan_message.dart';
import '../models/isbn.dart';
import '../models/return_date.dart';
import 'library_database.dart';
import '../services/cover_storage.dart';
import '../services/return_reminders.dart';

class DuplicateIsbnException implements Exception {
  const DuplicateIsbnException();

  static const message = 'Książka z tym numerem ISBN już istnieje.';

  @override
  String toString() => message;
}

class LibraryRepository {
  LibraryRepository(
      {LibraryDatabase? database,
      CoverStorage? coverStorage,
      this.reminders,
      DateTime Function()? clock})
      : _now = clock ?? DateTime.now,
        _database = database ?? LibraryDatabase.instance,
        coverStorage = coverStorage ?? CoverStorage();

  final CoverStorage coverStorage;
  final ReturnReminders? reminders;
  final DateTime Function() _now;

  DateTime get currentTime => _now();

  final LibraryDatabase _database;
  final _uuid = const Uuid();

  Future<LoanTransfer> loanInvitation(String bookId) async {
    final db = await _database.database;
    return db.transaction((txn) => _loanInvitation(txn, bookId));
  }

  Future<LoanTransfer> _loanInvitation(DatabaseExecutor txn, String bookId,
      {bool dateOnly = false}) async {
    final rows = await txn.query('books', where: 'id = ?', whereArgs: [bookId]);
    if (rows.isEmpty) throw StateError('Nie znaleziono książki.');
    final book = Book.fromMap(rows.single);
    if (book.status != BookStatus.borrowed || book.borrowedDate == null) {
      throw StateError('Brak aktywnego wypożyczenia.');
    }
    final instances = await txn.query('owner_loan_instances',
        where: 'book_id = ?', whereArgs: [bookId]);
    // Existing v3 active loans receive a durable ID without rewriting books/history.
    final loanId =
        instances.isEmpty ? _uuid.v4() : instances.single['loan_id']! as String;
    if (instances.isEmpty) {
      await txn.insert(
          'owner_loan_instances', {'book_id': bookId, 'loan_id': loanId});
    }
    final saved = await txn
        .query('loan_transfers', where: 'loan_id = ?', whereArgs: [loanId]);
    final old = saved.isEmpty
        ? null
        : LoanTransfer.decode(saved.single['payload']! as String);
    final isbn = normalizeIsbn(book.barcode);
    if (old != null &&
        (dateOnly ||
            (old.title == book.title &&
                old.author == book.author &&
                old.isbn == isbn)) &&
        old.returnDate == book.returnDate) {
      return old;
    }
    final invitation = LoanTransfer(
        transferId: old?.transferId ?? _uuid.v4(),
        loanId: loanId,
        bookId: book.id,
        title: dateOnly && old != null ? old.title : book.title,
        author: dateOnly && old != null ? old.author : book.author,
        isbn: dateOnly && old != null ? old.isbn : isbn,
        borrowedAt: book.borrowedDate!,
        returnDate: book.returnDate,
        issuedAt: _now(),
        revision: (old?.revision ?? 0) + 1);
    final payload = invitation.encode();
    LoanTransfer.decode(payload);
    await txn.insert('loan_transfers', {'loan_id': loanId, 'payload': payload},
        conflictAlgorithm: ConflictAlgorithm.replace);
    return invitation;
  }

  Future<List<LoanTransfer>> borrowedLoans() async {
    final db = await _database.database;
    final rows = await db.query('borrowed_loans', orderBy: 'rowid DESC');
    return rows
        .map((r) => LoanTransfer.decode(r['payload']! as String))
        .toList();
  }

  Future<void> importLoan(LoanTransfer invitation) async {
    final payload = invitation.encode();
    final incoming = LoanTransfer.decode(payload);
    final db = await _database.database;
    await db.transaction((txn) async {
      final rows = await txn.query('borrowed_loans',
          where: 'loan_id = ?', whereArgs: [incoming.loanId]);
      if (rows.isNotEmpty) {
        final old = LoanTransfer.decode(rows.single['payload']! as String);
        if (payload == old.encode()) return;
        if (incoming.transferId != old.transferId ||
            incoming.bookId != old.bookId ||
            incoming.borrowedAt != old.borrowedAt ||
            incoming.owner != old.owner ||
            incoming.revision <= old.revision ||
            incoming.issuedAt.isBefore(old.issuedAt)) {
          throw const FormatException(
              'Kod jest starszy lub koliduje z zapisanym wypożyczeniem.');
        }
        await txn.update('borrowed_loans',
            {'payload': payload, 'revision': incoming.revision},
            where: 'loan_id = ?', whereArgs: [incoming.loanId]);
      } else {
        await txn.insert('borrowed_loans', {
          'loan_id': incoming.loanId,
          'transfer_id': incoming.transferId,
          'payload': payload,
          'revision': incoming.revision
        });
      }
    });
  }

  Future<void> deleteBorrowedLoan(String loanId) async {
    final db = await _database.database;
    await db.transaction((txn) => txn
        .delete('borrowed_loans', where: 'loan_id = ?', whereArgs: [loanId]));
  }

  Future<void> _checkRequest(
      DatabaseExecutor txn, LoanMessage input, Book book) async {
    final request = LoanMessage.decode(input.encode());
    if (request.type != 'extension_request' ||
        request.bookId != book.id ||
        book.status != BookStatus.borrowed) {
      throw const FormatException('Prośba nie dotyczy aktywnego wypożyczenia.');
    }
    final instances = await txn.query('owner_loan_instances',
        where: 'book_id = ? AND loan_id = ?',
        whereArgs: [book.id, request.loanId]);
    final transfers = await txn.query('loan_transfers',
        where: 'loan_id = ?', whereArgs: [request.loanId]);
    final decisions = await txn.query('loan_messages',
        where: 'role = ? AND request_id = ?',
        whereArgs: ['owner', request.requestId]);
    if (decisions.isNotEmpty) {
      throw const FormatException(
          'Ta prośba ma już zapisaną decyzję. Otwórz ją w historii wiadomości.');
    }
    if (instances.isEmpty ||
        transfers.isEmpty ||
        !request.matches(
            LoanTransfer.decode(transfers.single['payload']! as String)) ||
        (book.returnDate == null ? null : calendarDate(book.returnDate!)) !=
            request.previousDate) {
      throw const FormatException(
          'Prośba dotyczy starszego terminu lub innego wypożyczenia.');
    }
    final validation =
        loanExtensionValidation(book.returnDate, request.newDate, _now());
    if (validation != null) throw FormatException(validation);
  }

  /// Read-only preview. Approval repeats these checks under SQLite's write lock.
  Future<Book> previewExtension(LoanMessage request) async {
    final db = await _database.database;
    return db.transaction((txn) async {
      final rows = await txn
          .query('books', where: 'id = ?', whereArgs: [request.bookId]);
      if (rows.isEmpty) throw const FormatException('Nie znaleziono książki.');
      final book = Book.fromMap(rows.single);
      await _checkRequest(txn, request, book);
      return book;
    });
  }

  Future<LoanMessage> decideExtension(
      LoanMessage request, bool approved) async {
    if (approved) {
      await _updateReturnDate(request.bookId, request.newDate,
          extension: true, request: request);
    } else {
      final db = await _database.database;
      await db.transaction((txn) async {
        final rows = await txn
            .query('books', where: 'id = ?', whereArgs: [request.bookId]);
        if (rows.isEmpty) {
          throw const FormatException('Nie znaleziono książki.');
        }
        await _checkRequest(txn, request, Book.fromMap(rows.single));
        final decision = request.decision(false, _now(), request.revision);
        await txn.insert('loan_messages', {
          'role': 'owner',
          'request_id': request.requestId,
          'loan_id': request.loanId,
          'request': request.encode(),
          'decision': decision.encode(),
          'state': 'rejected',
        });
      });
    }
    final rows = await messages('owner', loanId: request.loanId);
    return LoanMessage.decode(rows.singleWhere(
        (r) => r['request_id'] == request.requestId)['decision']! as String);
  }

  Future<LoanMessage> prepareExtension(String loanId, DateTime date) async {
    final db = await _database.database;
    return db.transaction((txn) async {
      final rows = await txn
          .query('borrowed_loans', where: 'loan_id = ?', whereArgs: [loanId]);
      if (rows.isEmpty || rows.single['local_status'] != 'active') {
        throw const FormatException('Brak aktywnego lokalnego wypożyczenia.');
      }
      final loan = LoanTransfer.decode(rows.single['payload']! as String);
      final validation = loanExtensionValidation(loan.returnDate, date, _now());
      if (validation != null) throw FormatException(validation);
      final request = LoanMessage(
          type: 'extension_request',
          requestId: _uuid.v4(),
          loanId: loan.loanId,
          bookId: loan.bookId,
          previousDate:
              loan.returnDate == null ? null : calendarDate(loan.returnDate!),
          newDate: calendarDate(date),
          revision: loan.revision,
          timestamp: _now());
      final code = request.encode();
      LoanMessage.decode(code);
      await txn.insert('loan_messages', {
        'role': 'borrower',
        'request_id': request.requestId,
        'loan_id': loanId,
        'request': code,
        'state': 'prepared'
      });
      return request;
    });
  }

  Future<List<Map<String, Object?>>> messages(String role,
      {String? loanId}) async {
    final db = await _database.database;
    return db.query('loan_messages',
        where: loanId == null ? 'role = ?' : 'role = ? AND loan_id = ?',
        whereArgs: loanId == null ? [role] : [role, loanId],
        orderBy: 'rowid DESC');
  }

  Future<void> markRequestSent(String requestId) async {
    final db = await _database.database;
    await db.update('loan_messages', {'state': 'pending'},
        where: "role = 'borrower' AND request_id = ? AND state = 'prepared'",
        whereArgs: [requestId]);
  }

  Future<LoanTransfer> _checkConfirmation(
      DatabaseExecutor txn, LoanMessage input) async {
    final message = LoanMessage.decode(input.encode());
    if (message.type != 'extension_approved') {
      throw const FormatException('Wklej kod zatwierdzonego przedłużenia.');
    }
    final rows = await txn.query('borrowed_loans',
        where: 'loan_id = ?', whereArgs: [message.loanId]);
    if (rows.isEmpty || rows.single['local_status'] != 'active') {
      throw const FormatException(
          'Nie znaleziono aktywnego wypożyczenia na tym urządzeniu.');
    }
    final loan = LoanTransfer.decode(rows.single['payload']! as String);
    final prior = await txn.query('loan_messages',
        where: "role = 'borrower' AND request_id = ?",
        whereArgs: [message.requestId]);
    if (prior.isNotEmpty && prior.single['state'] == 'imported') {
      if (prior.single['decision'] == message.encode()) return loan;
      throw const FormatException(
          'Konflikt kodów o tym samym identyfikatorze.');
    }
    if (!message.matches(loan) || message.timestamp.isBefore(loan.issuedAt)) {
      throw const FormatException(
          'Potwierdzenie dotyczy innego wypożyczenia lub starszego terminu.');
    }
    if (prior.isNotEmpty) {
      final request = LoanMessage.decode(prior.single['request']! as String);
      if (request.loanId != message.loanId ||
          request.bookId != message.bookId ||
          request.previousDate != message.previousDate ||
          request.newDate != message.newDate ||
          request.revision != message.revision) {
        throw const FormatException(
            'Potwierdzenie nie odpowiada zapisanej prośbie.');
      }
    }
    return loan;
  }

  Future<LoanTransfer> previewConfirmation(LoanMessage message) async {
    final db = await _database.database;
    return db.transaction((txn) => _checkConfirmation(txn, message));
  }

  Future<void> importConfirmation(LoanMessage message) async {
    final db = await _database.database;
    await db.transaction((txn) async {
      final loan = await _checkConfirmation(txn, message);
      final prior = await txn.query('loan_messages',
          where: "role = 'borrower' AND request_id = ?",
          whereArgs: [message.requestId]);
      if (prior.isNotEmpty && prior.single['state'] == 'imported') return;
      final updated = LoanTransfer(
          transferId: loan.transferId,
          loanId: loan.loanId,
          bookId: loan.bookId,
          title: loan.title,
          author: loan.author,
          isbn: loan.isbn,
          owner: loan.owner,
          borrowedAt: loan.borrowedAt,
          issuedAt: message.timestamp,
          returnDate: message.newDate,
          revision: message.newRevision!);
      final code = updated.encode();
      LoanTransfer.decode(code);
      await txn.update(
          'borrowed_loans', {'payload': code, 'revision': updated.revision},
          where: 'loan_id = ?', whereArgs: [loan.loanId]);
      if (prior.isEmpty) {
        await txn.insert('loan_messages', {
          'role': 'borrower',
          'request_id': message.requestId,
          'loan_id': message.loanId,
          'request': message.encode(),
          'decision': message.encode(),
          'state': 'imported'
        });
      } else {
        await txn.update('loan_messages',
            {'decision': message.encode(), 'state': 'imported'},
            where: "role = 'borrower' AND request_id = ?",
            whereArgs: [message.requestId]);
      }
    });
  }

  Future<String?> contact(String role, String loanId) async {
    final db = await _database.database;
    final rows = await db.query('loan_contacts',
        where: 'role = ? AND loan_id = ?', whereArgs: [role, loanId]);
    return rows.isEmpty ? null : rows.single['phone'] as String;
  }

  Future<void> saveContact(String role, String loanId, String phone) async {
    if (!RegExp(r'^[+0-9 ()-]{0,40}$').hasMatch(phone)) {
      throw const FormatException('Nieprawidłowy numer telefonu.');
    }
    final db = await _database.database;
    if (phone.trim().isEmpty) {
      await db.delete('loan_contacts',
          where: 'role = ? AND loan_id = ?', whereArgs: [role, loanId]);
    } else {
      await db.insert('loan_contacts',
          {'role': role, 'loan_id': loanId, 'phone': phone.trim()},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<List<Book>> books() async {
    final db = await _database.database;
    final rows = await db.query('books', orderBy: 'created_at DESC');
    return rows.map(Book.fromMap).toList();
  }

  Future<List<HistoryEntry>> history() async {
    final db = await _database.database;
    final rows = await db.query('history', orderBy: 'timestamp DESC');
    return rows.map(HistoryEntry.fromMap).toList();
  }

  static const bookHistoryLimit = 50;

  Future<List<HistoryEntry>> historyForBook(String bookId) async {
    final db = await _database.database;
    final rows = await db.query(
      'history',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'timestamp DESC, id DESC',
      limit: bookHistoryLimit,
    );
    return rows.map(HistoryEntry.fromMap).toList();
  }

  Future<void> _assertUniqueBarcode(DatabaseExecutor db, String? barcode,
      {String? exceptId}) async {
    if (barcode == null) return;
    final identity = bookBarcodeIdentity(barcode);
    final rows = await db.query('books',
        columns: ['barcode'],
        where: exceptId == null
            ? 'barcode IS NOT NULL'
            : 'id != ? AND barcode IS NOT NULL',
        whereArgs: exceptId == null ? null : [exceptId]);
    if (rows.any(
        (row) => bookBarcodeIdentity(row['barcode'] as String?) == identity)) {
      throw const DuplicateIsbnException();
    }
  }

  Future<Book> addBook({
    required String title,
    required String author,
    String description = '',
    String? coverUrl,
    String? barcode,
    String condition = 'Dobry',
    String directory = 'Bez kategorii',
  }) async {
    final normalizedBarcode = normalizeBookBarcode(barcode);
    final db = await _database.database;
    await _assertUniqueBarcode(db, normalizedBarcode);
    final storedCover = await coverStorage.persist(coverUrl);
    final now = _now();
    final book = Book(
      id: _uuid.v4(),
      title: title.trim(),
      author: author.trim(),
      description: description.trim(),
      coverUrl: storedCover,
      barcode: normalizedBarcode,
      condition: condition,
      directory: directory,
      createdAt: now,
      updatedAt: now,
    );
    try {
      await db.transaction((txn) async {
        // Recheck under SQLite's write lock, including equivalent 10/13 values
        // that the unchanged text-only unique index cannot compare.
        await _assertUniqueBarcode(txn, normalizedBarcode);
        try {
          await txn.insert('books', book.toMap());
        } on DatabaseException catch (error) {
          // The preflight check cannot prevent concurrent inserts. Translate only
          // the barcode unique constraint, leaving all other DB failures intact.
          if (normalizedBarcode != null &&
              error.isUniqueConstraintError('books.barcode')) {
            throw const DuplicateIsbnException();
          }
          rethrow;
        }
        await txn.insert(
            'history', _event(book, 'added', 'Dodano na półkę').toMap());
      });
    } catch (_) {
      if (storedCover != coverUrl) await _deleteUnusedCover(storedCover);
      rethrow;
    }
    return book;
  }

  /// Updates metadata only; loan state and linked history remain untouched.
  /// Additional metadata fields can be added here without changing loan writes.
  Future<Book> updateBook({
    required String id,
    required String title,
    required String author,
    String? barcode,
    required String condition,
    String? coverUrl,
    bool updateCover = false,
  }) async {
    if (title.trim().isEmpty || author.trim().isEmpty) {
      throw ArgumentError('Title and author are required');
    }
    final normalizedBarcode = normalizeBookBarcode(barcode);
    final db = await _database.database;
    final storedCover =
        updateCover ? await coverStorage.persist(coverUrl) : null;
    String? previousCover;
    late final Book result;
    try {
      result = await db.transaction((txn) async {
        final rows = await txn.query('books', where: 'id = ?', whereArgs: [id]);
        if (rows.isEmpty) throw StateError('Book no longer exists');
        final current = rows.single;
        previousCover = current['cover_url'] as String?;
        await _assertUniqueBarcode(txn, normalizedBarcode, exceptId: id);
        final changes = <String, Object?>{
          'title': title.trim(),
          'author': author.trim(),
          'barcode': normalizedBarcode,
          'condition': condition,
          if (updateCover) 'cover_url': storedCover,
        };
        if (changes.entries
            .every((entry) => current[entry.key] == entry.value)) {
          return Book.fromMap(current);
        }
        changes['updated_at'] = _now().toIso8601String();
        try {
          await txn.update('books', changes, where: 'id = ?', whereArgs: [id]);
        } on DatabaseException catch (error) {
          if (normalizedBarcode != null &&
              error.isUniqueConstraintError('books.barcode')) {
            throw const DuplicateIsbnException();
          }
          rethrow;
        }
        return Book.fromMap({...current, ...changes});
      });
    } catch (_) {
      // Only rollback-created files are candidates here; never existing covers.
      if (storedCover != coverUrl) await _deleteUnusedCover(storedCover);
      rethrow;
    }
    // The write has committed. Cleanup cannot change the saved result.
    if (updateCover && previousCover != storedCover) {
      await _deleteUnusedCover(previousCover);
    }
    return result;
  }

  Future<void> _refreshReminders() async {
    try {
      await reminders?.reconcile();
    } catch (error) {
      // Loan writes are committed; retry OS synchronization on next app resume.
      if (kDebugMode) debugPrint('Reminder synchronization failed: $error');
    }
  }

  Future<Book> updateReturnDate(String bookId, DateTime? date) =>
      _updateReturnDate(bookId, date);

  Future<Book> extendLoan(String bookId, DateTime date) =>
      _updateReturnDate(bookId, date, extension: true);

  Future<Book> _updateReturnDate(String bookId, DateTime? date,
      {bool extension = false, LoanMessage? request}) async {
    final db = await _database.database;
    var changed = false;
    final updated = await db.transaction((txn) async {
      final rows =
          await txn.query('books', where: 'id = ?', whereArgs: [bookId]);
      if (rows.isEmpty) {
        throw const ReturnDateException('Nie znaleziono książki.');
      }
      final current = Book.fromMap(rows.single);
      if (request != null) {
        await _checkRequest(txn, request, current);
        if (calendarDate(date!) != request.newDate) {
          throw const FormatException('Termin nie odpowiada prośbie.');
        }
      }
      if (current.status != BookStatus.borrowed) {
        throw const ReturnDateException(
            'Termin zwrotu można zmienić tylko dla wypożyczonej książki.');
      }
      final oldDate =
          current.returnDate == null ? null : calendarDate(current.returnDate!);
      final newDate = date == null ? null : calendarDate(date);
      final now = _now();
      if (extension) {
        final validation = loanExtensionValidation(oldDate, newDate, now);
        if (validation != null) throw ReturnDateException(validation);
      } else if (oldDate == newDate) {
        return current;
      }
      if (newDate != null && newDate.isBefore(calendarDate(now))) {
        throw const ReturnDateException(
            'Termin zwrotu nie może być w przeszłości.');
      }
      final changes = <String, Object?>{
        'return_date': newDate?.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };
      await txn.update('books', changes, where: 'id = ?', whereArgs: [bookId]);
      await txn.insert(
          'history',
          HistoryEntry(
            id: _uuid.v4(),
            bookId: current.id,
            bookTitle: current.title,
            action: extension ? 'loan_extended' : 'return_date_changed',
            detail:
                '${extension ? 'Przedłużono wypożyczenie' : 'Zmieniono termin zwrotu'}: ${returnDateHistoryValue(oldDate)} → ${returnDateHistoryValue(newDate)}',
            timestamp: now,
          ).toMap());
      // Only refresh an existing export. Ordinary date management must not
      // depend on whether a legacy loan can be represented by the QR protocol.
      final exported = await txn.rawQuery(
          'SELECT t.loan_id FROM loan_transfers t JOIN owner_loan_instances i ON t.loan_id = i.loan_id WHERE i.book_id = ?',
          [bookId]);
      final next = exported.isEmpty
          ? null
          : await _loanInvitation(txn, bookId, dateOnly: true);
      if (request != null) {
        final decision = request.decision(true, now, next!.revision);
        await txn.insert('loan_messages', {
          'role': 'owner',
          'request_id': request.requestId,
          'loan_id': request.loanId,
          'request': request.encode(),
          'decision': decision.encode(),
          'state': 'approved',
        });
      }
      changed = true;
      return Book.fromMap({...rows.single, ...changes});
    });
    if (changed) await _refreshReminders();
    return updated;
  }

  Future<void> lendBook(Book book, String borrower, DateTime? dueDate) =>
      _transitionLoan(book, 'borrowed', person: borrower, dueDate: dueDate);

  Future<void> giveBook(Book book, String recipient) =>
      _transitionLoan(book, 'given', person: recipient);

  Future<void> returnBook(Book book) => _transitionLoan(book, 'returned');

  Future<void> deleteBook(String bookId) async {
    final db = await _database.database;
    final previousCover = await db.transaction((txn) async {
      final rows = await txn.query('books',
          columns: ['cover_url'], where: 'id = ?', whereArgs: [bookId]);
      await txn.update('return_reminders', {'enabled': 0},
          where: 'book_id = ?', whereArgs: [bookId]);
      await txn.delete('books', where: 'id = ?', whereArgs: [bookId]);
      return rows.isEmpty ? null : rows.single['cover_url'] as String?;
    });
    await _refreshReminders();
    await _deleteUnusedCover(previousCover);
  }

  Future<void> _deleteUnusedCover(String? reference) async {
    if (reference == null || !CoverStorage.isManaged(reference)) return;
    try {
      final db = await _database.database;
      // Check and delete while holding SQLite's write lock, so another save
      // cannot start referencing this file between the check and deletion.
      await db.transaction((txn) async {
        final users = await txn.query('books',
            columns: ['id'],
            where: 'cover_url = ?',
            whereArgs: [reference],
            limit: 1);
        if (users.isEmpty) await coverStorage.delete(reference);
      });
    } catch (error, stackTrace) {
      // Cleanup is best effort, including unexpected storage/DB failures.
      // Preserve the original transaction error or successful committed result.
      if (kDebugMode) {
        debugPrint('Cover cleanup failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }
  }

  Future<void> _transitionLoan(Book snapshot, String action,
      {String? person, DateTime? dueDate}) async {
    final name = person?.trim();
    if (action != 'returned' && (name == null || name.isEmpty)) {
      throw ArgumentError('Wpisz imię osoby.');
    }
    final db = await _database.database;
    await db.transaction((txn) async {
      final rows = await txn.query('books',
          where: 'id = ?', whereArgs: [snapshot.id], limit: 1);
      if (rows.isEmpty) throw StateError('Nie znaleziono książki.');
      final current = Book.fromMap(rows.single);
      final valid = switch (action) {
        'borrowed' => current.status == BookStatus.available,
        'returned' => current.status == BookStatus.borrowed,
        'given' => current.status != BookStatus.given,
        _ => false,
      };
      if (!valid) throw StateError('Stan książki nie pozwala na tę operację.');
      if (snapshot.status != current.status) {
        throw StateError('Stan książki zmienił się. Odśwież dane książki.');
      }
      if (current.status == BookStatus.borrowed &&
          action != 'borrowed' &&
          (current.status != BookStatus.borrowed ||
              snapshot.borrowedDate != current.borrowedDate ||
              snapshot.borrowedBy != current.borrowedBy)) {
        throw StateError('Wypożyczenie zmieniło się. Odśwież dane książki.');
      }
      final now = _now();
      final changes = <String, Object?>{
        'status': switch (action) {
          'borrowed' => 'borrowed',
          'given' => 'given',
          _ => 'available',
        },
        'borrowed_by': action == 'returned' ? null : name,
        'borrowed_date': action == 'returned'
            ? null
            : action == 'given' && current.status == BookStatus.borrowed
                ? current.borrowedDate?.toIso8601String()
                : now.toIso8601String(),
        'return_date': action == 'borrowed' ? dueDate?.toIso8601String() : null,
        'updated_at': now.toIso8601String(),
      };
      // Never write metadata from a potentially stale UI snapshot.
      await txn
          .update('books', changes, where: 'id = ?', whereArgs: [current.id]);
      final detail = switch (action) {
        'borrowed' => 'Wypożyczono: $name',
        'given' => 'Oddano na stałe: $name',
        _ => 'Oznaczono jako zwróconą',
      };
      final event = _event(current, action, detail, now);
      await txn.insert('history', event.toMap());
      await txn.delete('owner_loan_instances',
          where: 'book_id = ?', whereArgs: [current.id]);
      if (action == 'borrowed') {
        await txn.insert('owner_loan_instances',
            {'book_id': current.id, 'loan_id': event.id});
      }
      await txn.update('return_reminders', {'enabled': 0},
          where: 'book_id = ?', whereArgs: [current.id]);
    });
    await _refreshReminders();
  }

  HistoryEntry _event(Book book, String action,
          [String? detail, DateTime? at]) =>
      HistoryEntry(
        id: _uuid.v4(),
        bookId: book.id,
        bookTitle: book.title,
        action: action,
        detail: detail,
        timestamp: at ?? _now(),
      );
}
