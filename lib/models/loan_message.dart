import 'dart:convert';

import 'loan_transfer.dart';
import 'return_date.dart';
import 'readable_loan.dart';

/// Untrusted offline v1 messages, using the same envelope as QR invitations.
class LoanMessage {
  const LoanMessage({
    required this.type,
    required this.requestId,
    required this.loanId,
    required this.bookId,
    required this.previousDate,
    required this.newDate,
    required this.revision,
    required this.timestamp,
    this.newRevision,
  });

  final String type, requestId, loanId, bookId;
  final DateTime? previousDate;
  final DateTime newDate, timestamp;
  final int revision;
  final int? newRevision;

  Map<String, Object?> toJson() => {
        'p': 'moja-biblioteka',
        'v': 1,
        't': type,
        'id': requestId,
        'loan': loanId,
        'book': bookId,
        'due': previousDate == null ? null : _date(previousDate!),
        'new_due': _date(newDate),
        'revision': revision,
        'new_revision': newRevision,
        'issued': timestamp.toUtc().toIso8601String(),
      };

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String encode() {
    final code = LoanTransfer.prefix +
        base64Url.encode(utf8.encode(jsonEncode(toJson()))).replaceAll('=', '');
    if (code.length > LoanTransfer.maxLength) {
      throw const FormatException('Kod jest za długi.');
    }
    return code;
  }

  static LoanMessage decode(String input) {
    try {
      if (input.length > LoanTransfer.maxLength) throw const FormatException();
      final code = input.trim();
      if (!code.startsWith(LoanTransfer.prefix)) throw const FormatException();
      final map = jsonDecode(utf8.decode(base64Url.decode(
          base64Url.normalize(code.substring(LoanTransfer.prefix.length)))));
      if (map is! Map<String, dynamic> ||
          map['p'] != 'moja-biblioteka' ||
          map['v'] is! int ||
          map['v'] != 1 ||
          !const [
            'extension_request',
            'extension_approved',
            'extension_rejected'
          ].contains(map['t'])) {
        throw const FormatException();
      }
      String field(String key, int max) {
        final v = map[key];
        if (v is! String ||
            v.trim().isEmpty ||
            v.length > max ||
            v.runes.any((c) => c < 32 || c == 127)) {
          throw const FormatException();
        }
        return v;
      }

      DateTime date(String key) {
        final s = field(key, 10);
        if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) {
          throw const FormatException();
        }
        final d = DateTime.parse(s);
        if (_date(d) != s || d.year < 1900 || d.year > 2200) {
          throw const FormatException();
        }
        return d;
      }

      int revision(String key) {
        final v = map[key];
        if (v is! int || v < 1 || v > 2147483647) throw const FormatException();
        return v;
      }

      final stamp = field('issued', 32);
      final timestamp = DateTime.tryParse(stamp);
      if (timestamp == null ||
          !stamp.endsWith('Z') ||
          timestamp.toUtc().toIso8601String() != stamp ||
          timestamp.year < 1900 ||
          timestamp.year > 2200) {
        throw const FormatException();
      }
      final old = map['due'] == null ? null : date('due');
      final next = date('new_due');
      if (old != null && !next.isAfter(old)) throw const FormatException();
      final rev = revision('revision');
      final newRev =
          map['t'] == 'extension_approved' ? revision('new_revision') : null;
      if (newRev != null && newRev <= rev) throw const FormatException();
      return LoanMessage(
          type: map['t'] as String,
          requestId: field('id', 80),
          loanId: field('loan', 80),
          bookId: field('book', 80),
          previousDate: old,
          newDate: next,
          revision: rev,
          newRevision: newRev,
          timestamp: timestamp);
    } catch (_) {
      throw const FormatException(
          'Nieprawidłowy lub nieobsługiwany kod wiadomości.');
    }
  }

  LoanMessage decision(bool approved, DateTime now, int nextRevision) =>
      LoanMessage(
          type: approved ? 'extension_approved' : 'extension_rejected',
          requestId: requestId,
          loanId: loanId,
          bookId: bookId,
          previousDate: previousDate,
          newDate: newDate,
          revision: revision,
          newRevision: approved ? nextRevision : null,
          timestamp: now);

  bool matches(LoanTransfer loan) =>
      loan.loanId == loanId &&
      loan.bookId == bookId &&
      loan.revision == revision &&
      (loan.returnDate == null ? null : calendarDate(loan.returnDate!)) ==
          previousDate;
}

String invitationMessage(LoanTransfer loan) => readableInvitation(loan);

String extensionMessage(LoanMessage message, String title,
        {String owner = 'Nie podano'}) =>
    withInstallationLink(message.type == 'extension_request'
        ? 'Moja Biblioteka — prośba o przedłużenie\n\nKsiążka: $title\nWłaściciel: $owner\n'
            'Obecny termin zwrotu: ${returnDateHistoryValue(message.previousDate)}\n'
            'Proponowany termin zwrotu: ${formatReturnDate(message.newDate)}'
        : message.type == 'extension_approved'
            ? 'Moja Biblioteka — zatwierdzenie przedłużenia\n\nKsiążka: $title\n'
                'Nowy termin zwrotu: ${formatReturnDate(message.newDate)}'
            : 'Moja Biblioteka — odmowa przedłużenia\n\nKsiążka: $title\n'
                'Termin zwrotu pozostaje bez zmian: ${returnDateHistoryValue(message.previousDate)}');
