import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/screens/scan_book_screen.dart';

void main() {
  group('normalizeIsbn', () {
    test('accepts a valid ISBN-13', () {
      expect(normalizeIsbn('978-0-525-55947-4'), '9780525559474');
    });

    test('accepts a valid ISBN-10 ending in X', () {
      expect(normalizeIsbn('0-8044-2957-X'), '080442957X');
    });

    test('rejects an invalid ISBN', () {
      expect(normalizeIsbn('9780525559475'), isNull);
      expect(normalizeIsbn('hello'), isNull);
    });
  });
}
