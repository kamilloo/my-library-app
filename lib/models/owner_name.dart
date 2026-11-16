const ownerNameMaxLength = 120;

/// Optional, user-provided QR label; never an identity assertion.
String? validateOwnerName(String input) {
  if (input.runes.any(
      (c) => c < 32 || (c >= 127 && c <= 159) || c == 0x2028 || c == 0x2029)) {
    throw const FormatException(
        'Właściciel: usuń znaki sterujące i nowe linie.');
  }
  final name = input.trim();
  if (name.length > ownerNameMaxLength) {
    throw const FormatException('Właściciel: maksymalnie 120 znaków.');
  }
  return name.isEmpty ? null : name;
}
