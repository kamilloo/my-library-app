import 'isbn.dart';
import 'loan_transfer.dart';
import 'return_date.dart';

/// Set only after verifying the public listing. Empty by default.
const configuredPlayUrl = String.fromEnvironment('VERIFIED_GOOGLE_PLAY_URL');

String? verifiedPlayUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != 'play.google.com' ||
      uri.path != '/store/apps/details' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      uri.fragment.isNotEmpty ||
      uri.queryParameters.length != 1 ||
      uri.queryParametersAll['id']?.length != 1 ||
      !RegExp(r'^[a-zA-Z]\w*(?:\.\w+)+$')
          .hasMatch(uri.queryParameters['id'] ?? '')) {
    return null;
  }
  return value;
}

String withInstallationLink(String message, {String url = configuredPlayUrl}) {
  final link = verifiedPlayUrl(url);
  return link == null ? message : '$message\n\n$link';
}

class ReadableLoan {
  const ReadableLoan(
      {required this.title,
      required this.author,
      required this.owner,
      required this.borrowedAt,
      this.returnDate,
      this.isbn});
  final String title, author, owner;
  final DateTime borrowedAt;
  final DateTime? returnDate;
  final String? isbn;
  static const header = 'Moja Biblioteka — informacja o wypożyczeniu';
  static const maxLength = 3000;

  static String field(String value, String label, int max) {
    final text = value.trim();
    if (text.isEmpty ||
        text.length > max ||
        text.runes.any((c) => c < 32 || c == 127)) {
      throw FormatException(
          'Uzupełnij poprawnie pole „$label” (do $max znaków).');
    }
    return text;
  }

  ReadableLoan validated() {
    final code = isbn?.trim();
    final normalized =
        code == null || code.isEmpty ? null : normalizeIsbn(code);
    if (code != null && code.isNotEmpty && normalized == null) {
      throw const FormatException('Nieprawidłowy ISBN.');
    }
    for (final date in [borrowedAt, returnDate]) {
      if (date != null && (date.year < 1900 || date.year > 2200)) {
        throw const FormatException('Data musi być z lat 1900–2200.');
      }
    }
    if (returnDate != null &&
        calendarDate(returnDate!).isBefore(calendarDate(borrowedAt))) {
      throw const FormatException(
          'Termin zwrotu nie może poprzedzać daty wypożyczenia.');
    }
    return ReadableLoan(
        title: field(title, 'Tytuł', 240),
        author: field(author, 'Autor', 160),
        owner: field(owner, 'Właściciel', 120),
        borrowedAt: calendarDate(borrowedAt),
        returnDate: returnDate == null ? null : calendarDate(returnDate!),
        isbn: normalized);
  }

  static DateTime parseDate(String value) {
    final match = RegExp(r'^(\d{2})\.(\d{2})\.(\d{4})$').firstMatch(value);
    if (match == null) {
      throw const FormatException('Użyj daty w formacie DD.MM.RRRR.');
    }
    final day = int.parse(match[1]!),
        month = int.parse(match[2]!),
        year = int.parse(match[3]!);
    final date = DateTime(year, month, day);
    if (date.day != day ||
        date.month != month ||
        date.year != year ||
        year < 1900 ||
        year > 2200) {
      throw const FormatException('Nieprawidłowa data.');
    }
    return date;
  }

  static String canonicalSms(String input) =>
      input.replaceAll('\r\n', '\n').trim();

  static ReadableLoan parse(String input,
      {required DateTime today, String url = configuredPlayUrl}) {
    if (input.length > maxLength) {
      throw const FormatException(
          'Wiadomość jest za długa (maksymalnie 3000 znaków).');
    }
    final normalized = canonicalSms(input);
    if (normalized.runes.any((c) => (c < 32 && c != 10) || c == 127)) {
      throw const FormatException(
          'Wiadomość zawiera niedozwolone znaki sterujące.');
    }
    final lines = normalized.split('\n');
    if (lines.first != header) {
      throw const FormatException(
          'Wklej wiadomość z obsługiwanym nagłówkiem Moja Biblioteka.');
    }
    final values = <String, String>{};
    const labels = [
      'Książka',
      'Autor',
      'Właściciel',
      'Data wypożyczenia',
      'Termin zwrotu',
      'ISBN'
    ];
    var afterLink = false;
    for (final line in lines.skip(1)) {
      if (line.trim().isEmpty) continue;
      if (verifiedPlayUrl(url) != null && line == url) {
        if (afterLink) {
          throw const FormatException('Powtórzony link instalacyjny.');
        }
        afterLink = true;
        continue;
      }
      final separator = line.indexOf(': ');
      if (afterLink || separator < 0) {
        throw const FormatException('Nieobsługiwany wiersz wiadomości.');
      }
      final key = line.substring(0, separator);
      if (!labels.contains(key) || values.containsKey(key)) {
        throw const FormatException('Nieznane lub powtórzone pole wiadomości.');
      }
      values[key] = line.substring(separator + 2).trim();
    }
    DateTime? date(String key) =>
        values.containsKey(key) ? parseDate(values[key]!) : null;
    return ReadableLoan(
            title: values['Książka'] ?? '',
            author: values['Autor'] ?? '',
            owner: values['Właściciel'] ?? '',
            borrowedAt: date('Data wypożyczenia') ?? calendarDate(today),
            returnDate: date('Termin zwrotu'),
            isbn: values['ISBN'])
        .validated();
  }
}

String readableInvitation(LoanTransfer loan,
        {String url = configuredPlayUrl}) =>
    withInstallationLink(
        '${ReadableLoan.header}\n\n'
        'Książka: ${loan.title}\nAutor: ${loan.author}\n'
        'Właściciel: ${loan.owner ?? 'Nie podano'}\n'
        'Data wypożyczenia: ${formatReturnDate(loan.borrowedAt)}'
        '${loan.returnDate == null ? '' : '\nTermin zwrotu: ${formatReturnDate(loan.returnDate!)}'}'
        '${loan.isbn == null ? '' : '\nISBN: ${loan.isbn}'}',
        url: url);
