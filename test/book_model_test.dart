import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/models/book.dart';

void main() {
  test('book survives a database map round trip', () {
    final now = DateTime(2026, 9, 23, 12);
    final book = Book(
      id: 'book-1',
      title: 'The Midnight Library',
      author: 'Matt Haig',
      barcode: '9780525559474',
      createdAt: now,
      updatedAt: now,
    );

    final restored = Book.fromMap(book.toMap());

    expect(restored.id, book.id);
    expect(restored.title, book.title);
    expect(restored.status, BookStatus.available);
    expect(restored.barcode, '9780525559474');
  });
}
