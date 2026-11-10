DateTime calendarDate(DateTime value) =>
    DateTime(value.year, value.month, value.day);

// Calendar arithmetic preserves midnight across month ends and DST changes.
DateTime extendedReturnDate(DateTime current, int days) =>
    DateTime(current.year, current.month, current.day + days);

String? loanExtensionValidation(
    DateTime? old, DateTime? proposed, DateTime now) {
  if (proposed == null) return 'Wybierz nowy termin zwrotu.';
  final date = calendarDate(proposed);
  if (old != null && !date.isAfter(calendarDate(old))) {
    return 'Nowy termin musi być późniejszy niż obecny termin zwrotu.';
  }
  if (!date.isAfter(calendarDate(now))) {
    return 'Termin prolongaty musi przypadać po dzisiejszym dniu.';
  }
  return null;
}

String formatReturnDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';

String returnDateHistoryValue(DateTime? date) =>
    date == null ? 'Nie ustawiono terminu zwrotu' : formatReturnDate(date);

class ReturnDateException implements Exception {
  const ReturnDateException(this.message);
  final String message;
  @override
  String toString() => message;
}
