import 'dart:convert';

import 'isbn.dart';

/// Offline protocol v1. No identity or ownership verification is implied.
class LoanTransfer {
  const LoanTransfer({
    required this.transferId,
    required this.loanId,
    required this.bookId,
    required this.title,
    required this.author,
    required this.borrowedAt,
    required this.issuedAt,
    required this.revision,
    this.returnDate,
    this.isbn,
    this.owner,
  });
  final String transferId, loanId, bookId, title, author;
  final String? isbn, owner;
  final DateTime borrowedAt, issuedAt;
  final DateTime? returnDate;
  final int revision;

  Map<String, Object?> toJson() => {
        'p': 'moja-biblioteka',
        'v': 1,
        't': 'loan_invitation',
        'id': transferId,
        'loan': loanId,
        'book': bookId,
        'title': title,
        'author': author,
        'isbn': isbn,
        'owner': owner,
        'borrowed': borrowedAt.toIso8601String(),
        'due': returnDate?.toIso8601String(),
        'issued': issuedAt.toUtc().toIso8601String(),
        'revision': revision,
      };

  static const prefix = 'moja-biblioteka:';
  static const maxLength = 2400;
  String encode() {
    final code = prefix +
        base64Url.encode(utf8.encode(jsonEncode(toJson()))).replaceAll('=', '');
    if (code.length > maxLength) {
      throw const FormatException('Kod jest za długi.');
    }
    return code;
  }

  static LoanTransfer decode(String input) {
    try {
      if (input.length > maxLength) {
        throw const FormatException();
      }
      final code = input.trim();
      if (code.length > maxLength || !code.startsWith(prefix)) {
        throw const FormatException();
      }
      final map = jsonDecode(utf8.decode(base64Url
          .decode(base64Url.normalize(code.substring(prefix.length)))));
      if (map is! Map<String, dynamic> ||
          map['p'] != 'moja-biblioteka' ||
          map['v'] is! int ||
          map['v'] != 1 ||
          map['t'] != 'loan_invitation') {
        throw const FormatException();
      }
      String field(String key, int max) {
        final value = map[key];
        if (value is! String ||
            value.trim().isEmpty ||
            value.length > max ||
            value.runes.any((c) => c < 32)) {
          throw const FormatException();
        }
        return value;
      }

      String? optional(String key, int max) =>
          map[key] == null ? null : field(key, max);
      DateTime date(String key) {
        final value = field(key, 40);
        final parts =
            RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:T|$)').firstMatch(value);
        if (parts == null) {
          throw const FormatException();
        }
        final year = int.parse(parts[1]!);
        final month = int.parse(parts[2]!);
        final day = int.parse(parts[3]!);
        final calendar = DateTime.utc(year, month, day);
        if (calendar.year != year ||
            calendar.month != month ||
            calendar.day != day) {
          throw const FormatException();
        }
        if (key == 'issued' && !value.endsWith('Z')) {
          throw const FormatException();
        }
        final time = RegExp(
                r'T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})?$')
            .firstMatch(value);
        if (value.contains('T') &&
            (time == null ||
                int.parse(time[1]!) > 23 ||
                int.parse(time[2]!) > 59 ||
                int.parse(time[3]!) > 59)) {
          throw const FormatException();
        }
        final parsed = DateTime.tryParse(value);
        if (parsed == null || parsed.year < 1900 || parsed.year > 2200) {
          throw const FormatException();
        }
        return parsed;
      }

      final isbn = optional('isbn', 13);
      if (isbn != null && normalizeIsbn(isbn) != isbn) {
        throw const FormatException();
      }
      final revision = map['revision'];
      if (revision is! int || revision < 1 || revision > 2147483647) {
        throw const FormatException();
      }
      final borrowed = date('borrowed');
      final due = map['due'] == null ? null : date('due');
      if (due != null &&
          DateTime.utc(due.year, due.month, due.day).isBefore(
              DateTime.utc(borrowed.year, borrowed.month, borrowed.day))) {
        throw const FormatException();
      }
      return LoanTransfer(
        transferId: field('id', 80),
        loanId: field('loan', 80),
        bookId: field('book', 80),
        title: field('title', 240),
        author: field('author', 160),
        owner: optional('owner', 120),
        isbn: isbn,
        borrowedAt: borrowed,
        issuedAt: date('issued'),
        returnDate: due,
        revision: revision,
      );
    } catch (_) {
      throw const FormatException(
          'Nieprawidłowy lub nieobsługiwany kod wypożyczenia.');
    }
  }
}
