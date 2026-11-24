import 'dart:async';

import 'package:booknotes/core/contracts/contracts.dart';
import 'package:booknotes/core/models/book.dart';

/// Test-only in-memory [BookRepository] with sample books.
/// Not used by the app; production uses TxtBookRepository.
class InMemoryBookRepository implements BookRepository {
  InMemoryBookRepository(List<Book> seed) : _books = List.of(seed);

  factory InMemoryBookRepository.withSamples() =>
      InMemoryBookRepository(_samples(DateTime.now()));

  final List<Book> _books;
  final _changes = StreamController<List<Book>>.broadcast();

  void _emit() => _changes.add(List.unmodifiable(_books));
  void dispose() => _changes.close();

  @override
  Stream<List<Book>> watchBooks() async* {
    yield List.unmodifiable(_books);
    yield* _changes.stream;
  }

  @override
  Future<List<Book>> listBooks() async => List.unmodifiable(_books);

  @override
  Future<Book> createBook(NewBookRequest r) async {
    final id = 'book-${DateTime.now().microsecondsSinceEpoch}';
    final book = Book(
      id: id,
      title: r.title,
      subject: r.subject,
      folderRef: 'memory://$id',
      cover: BookCoverRef(
        imagePath: r.coverImagePath,
        colorValue: r.coverColorValue,
      ),
      pageCount: 1,
    );
    _books.add(book);
    _emit();
    return book;
  }

  @override
  Future<void> updateBook(Book book) async {
    final i = _books.indexWhere((b) => b.id == book.id);
    if (i >= 0) {
      _books[i] = book;
      _emit();
    }
  }

  @override
  Future<void> deleteBook(String bookId) async {
    _books.removeWhere((b) => b.id == bookId);
    _emit();
  }

  @override
  Future<void> markOpened(String bookId, {int? page}) async {
    final i = _books.indexWhere((b) => b.id == bookId);
    if (i < 0) return;
    _books[i] = _books[i].copyWith(
      lastOpenedAt: DateTime.now(),
      lastOpenedPage: page,
    );
    _emit();
  }

  @override
  Future<List<Book>> importFolder(String folderPath) async => const [];

  static List<Book> _samples(DateTime now) {
    Book b(
      int n,
      String title,
      String subject,
      int pages,
      Duration? ago,
      int color,
    ) =>
        Book(
          id: 'sample-$n',
          title: title,
          subject: subject,
          folderRef: 'memory://sample-$n',
          cover: BookCoverRef(colorValue: color),
          pageCount: pages,
          lastOpenedPage: ago == null ? 1 : (pages ~/ 3).clamp(1, pages),
          lastOpenedAt: ago == null ? null : now.subtract(ago),
        );
    return [
      b(
        1,
        'Astronomy Field Notes',
        'Science',
        48,
        const Duration(hours: 2),
        0xFF1F3A5F,
      ),
      b(
        2,
        'Kitchen Experiments',
        'Cooking',
        32,
        const Duration(days: 1),
        0xFF8A3B12,
      ),
      b(
        3,
        'Flutter Study Journal',
        'Programming',
        120,
        const Duration(days: 3),
        0xFF0F5D5A,
      ),
      b(4, 'Monsoon Poems', 'Poetry', 24, const Duration(days: 5), 0xFF5B2A63),
      b(
        5,
        'Linear Algebra',
        'Mathematics',
        86,
        const Duration(days: 9),
        0xFF2F4A2A,
      ),
      b(
        6,
        'Travel Diary: Kerala',
        'Travel',
        64,
        const Duration(days: 16),
        0xFF7A2E2E,
      ),
      b(7, 'Garden Log', 'Hobbies', 18, const Duration(days: 40), 0xFF4D5A1E),
      b(8, 'Startup Ideas', 'Business', 27, null, 0xFF3B3B52),
      b(
        9,
        'Meeting Minutes 2026',
        'Work',
        210,
        const Duration(days: 70),
        0xFF5A4630,
      ),
    ];
  }
}
