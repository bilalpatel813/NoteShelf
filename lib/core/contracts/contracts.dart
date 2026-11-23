/// Integration contracts. T1 defines them; later tasks implement or consume.
///
///  * [BookRepository]   -> implemented by T2 (TXT/folder storage)
///  * [PageRepository]   -> implemented by T2, consumed by T3/T4/T5
///  * [BookshelfActions] -> New Book / Import Folder / Open Book hooks.
///        T2 supplies real New Book + Import Folder flows,
///        T3 supplies the real "open reader" navigation.
///
/// Wire-up point: override the providers declared in
/// `features/bookshelf/bookshelf_providers.dart` via
/// `ProviderScope(overrides: [...])` in main.dart.
library;

import 'package:flutter/widgets.dart';

import '../models/book.dart';

class NewBookRequest {
  const NewBookRequest({
    required this.title,
    this.subject = 'General',
    this.coverColorValue = 0xFF7A2E2E,
    this.coverImagePath,
  });

  final String title;
  final String subject;
  final int coverColorValue;
  final String? coverImagePath;
}

abstract interface class BookRepository {
  /// Emits the current list immediately, then again after every change.
  Stream<List<Book>> watchBooks();
  Future<List<Book>> listBooks();

  /// Creates the book (and its folder in T2). Returns the stored book.
  Future<Book> createBook(NewBookRequest request);
  Future<void> updateBook(Book book);

  /// Removes the book from the library. T2 decides whether files are deleted.
  Future<void> deleteBook(String bookId);

  /// Sets lastOpenedAt = now; sets lastOpenedPage when [page] is given.
  Future<void> markOpened(String bookId, {int? page});

  /// Scans [folderPath] for TXT pages and registers it as a book.
  Future<List<Book>> importFolder(String folderPath);
}

abstract interface class PageRepository {
  Future<List<BookPage>> listPages(String bookId);
  Future<BookPage?> readPage(String bookId, int pageNumber);
  Future<BookPage> createPage(String bookId, {int? atNumber});
  Future<void> writePage(BookPage page);
  Future<void> deletePage(String bookId, int pageNumber);
}

/// UI-level hooks used by the bookshelf. Each receives a [BuildContext] so an
/// implementation can show dialogs / pickers / push routes.
abstract interface class BookshelfActions {
  /// "New Book" button / FAB. T2 replaces with a real creation flow.
  Future<void> newBook(BuildContext context);

  /// "Import Folder" button. T2 replaces with folder picker + importFolder().
  Future<void> importFolder(BuildContext context);

  /// Double-click (Windows) / tap (Android) / "Open" menu item.
  /// T3 replaces with navigation to the reader and calls markOpened().
  Future<void> openBook(BuildContext context, Book book);
}
