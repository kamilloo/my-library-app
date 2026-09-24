enum BookStatus { available, borrowed, given }

class Book {
  const Book({
    required this.id,
    required this.title,
    required this.author,
    required this.createdAt,
    required this.updatedAt,
    this.description = '',
    this.coverUrl,
    this.barcode,
    this.condition = 'Good',
    this.directory = 'Unsorted',
    this.status = BookStatus.available,
    this.borrowedBy,
    this.borrowedDate,
    this.returnDate,
  });

  final String id;
  final String title;
  final String author;
  final String description;
  final String? coverUrl;
  final String? barcode;
  final String condition;
  final String directory;
  final BookStatus status;
  final String? borrowedBy;
  final DateTime? borrowedDate;
  final DateTime? returnDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  Book copyWith({
    BookStatus? status,
    String? borrowedBy,
    DateTime? borrowedDate,
    DateTime? returnDate,
    bool clearLoan = false,
  }) => Book(
        id: id,
        title: title,
        author: author,
        description: description,
        coverUrl: coverUrl,
        barcode: barcode,
        condition: condition,
        directory: directory,
        status: status ?? this.status,
        borrowedBy: clearLoan ? null : borrowedBy ?? this.borrowedBy,
        borrowedDate: clearLoan ? null : borrowedDate ?? this.borrowedDate,
        returnDate: clearLoan ? null : returnDate ?? this.returnDate,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'author': author,
        'description': description,
        'cover_url': coverUrl,
        'barcode': barcode,
        'condition': condition,
        'directory': directory,
        'status': status.name,
        'borrowed_by': borrowedBy,
        'borrowed_date': borrowedDate?.toIso8601String(),
        'return_date': returnDate?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Book.fromMap(Map<String, Object?> map) => Book(
        id: map['id']! as String,
        title: map['title']! as String,
        author: map['author']! as String,
        description: (map['description'] as String?) ?? '',
        coverUrl: map['cover_url'] as String?,
        barcode: map['barcode'] as String?,
        condition: (map['condition'] as String?) ?? 'Good',
        directory: (map['directory'] as String?) ?? 'Unsorted',
        status: BookStatus.values.byName(map['status']! as String),
        borrowedBy: map['borrowed_by'] as String?,
        borrowedDate: DateTime.tryParse((map['borrowed_date'] as String?) ?? ''),
        returnDate: DateTime.tryParse((map['return_date'] as String?) ?? ''),
        createdAt: DateTime.parse(map['created_at']! as String),
        updatedAt: DateTime.parse(map['updated_at']! as String),
      );
}

class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.bookId,
    required this.bookTitle,
    required this.action,
    required this.timestamp,
    this.detail,
  });

  final String id;
  final String bookId;
  final String bookTitle;
  final String action;
  final String? detail;
  final DateTime timestamp;

  Map<String, Object?> toMap() => {
        'id': id,
        'book_id': bookId,
        'book_title': bookTitle,
        'action': action,
        'detail': detail,
        'timestamp': timestamp.toIso8601String(),
      };

  factory HistoryEntry.fromMap(Map<String, Object?> map) => HistoryEntry(
        id: map['id']! as String,
        bookId: map['book_id']! as String,
        bookTitle: map['book_title']! as String,
        action: map['action']! as String,
        detail: map['detail'] as String?,
        timestamp: DateTime.parse(map['timestamp']! as String),
      );
}
