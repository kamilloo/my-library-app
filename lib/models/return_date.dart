DateTime calendarDate(DateTime value) =>
    DateTime(value.year, value.month, value.day);

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
