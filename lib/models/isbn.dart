String? normalizeIsbn(String? rawValue) {
  if (rawValue == null) return null;
  final value = rawValue.replaceAll(RegExp('[^0-9Xx]'), '').toUpperCase();
  if (value.length == 10 && _validIsbn10(value)) return value;
  if (value.length == 13 && _validIsbn13(value)) return value;
  return null;
}

bool _validIsbn10(String value) {
  var sum = 0;
  for (var index = 0; index < 10; index++) {
    final character = value[index];
    final digit = character == 'X' && index == 9 ? 10 : int.tryParse(character);
    if (digit == null) return false;
    sum += digit * (10 - index);
  }
  return sum % 11 == 0;
}

bool _validIsbn13(String value) {
  var sum = 0;
  for (var index = 0; index < 13; index++) {
    final digit = int.tryParse(value[index]);
    if (digit == null) return false;
    sum += digit * (index.isEven ? 1 : 3);
  }
  return sum % 10 == 0;
}

// Preserve support for non-ISBN barcodes and SQLite's nullable unique index.
String? normalizeBookBarcode(String? rawValue) {
  final value = rawValue?.trim();
  if (value == null || value.isEmpty) return null;
  return normalizeIsbn(value) ?? value;
}
