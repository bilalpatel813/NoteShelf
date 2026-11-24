/// T2 - the classes named in the handoff: TxtBookRepository and
/// TxtPageRepository, thin adapters over [BookStore]. Everything the T1
/// contracts cannot express (rename heading, move page, export, relink...) is
/// reachable via `.store` / [BookTransfer].
library;

import '../../core/contracts/contracts.dart';
import '../../core/models/book.dart';
import 'book_store.dart';
import 'book_transfer.dart';
import 'storage_platform.dart';

class TxtBookRepository implements BookRepository {
  TxtBookRepository(this.store, {this.platform});

  final BookStore store;

  /// Needed only by UI flows (pickers). Null in unit tests.
  final StoragePlatform? platform;

  @override
  Stream<List<Book>> watchBooks() => store.watchBooks();

  @override
  Future<List<Book>> listBooks() => store.listBooks();

  @override
  Future<Book> createBook(NewBookRequest request) => store.createBook(request);

  @override
  Future<void> updateBook(Book book) => store.updateBook(book);

  /// Internal books go to Trash/ (30 days); linked folders are only unlinked.
  @override
  Future<void> deleteBook(String bookId) => store.deleteBook(bookId);

  @override
  Future<void> markOpened(String bookId, {int? page}) =>
      store.markOpened(bookId, page: page);

  /// Contract method; the extra [mode] defaults to copy. Pass
  /// [ImportMode.link] to keep using the folder in place.
  @override
  Future<List<Book>> importFolder(
    String folderPath, {
    ImportMode mode = ImportMode.copy,
  }) =>
      store.importFolder(folderPath, mode: mode);

  BookTransfer get transfer => BookTransfer(store);
}

class TxtPageRepository implements PageRepository {
  TxtPageRepository(this.store);

  final BookStore store;

  /// Pages in order; `content` is EMPTY unless [withContent] is true. Use
  /// readPage() to get one page's text.
  @override
  Future<List<BookPage>> listPages(String bookId, {bool withContent = false}) =>
      store.listPages(bookId, withContent: withContent);

  @override
  Future<BookPage?> readPage(String bookId, int pageNumber) =>
      store.readPage(bookId, pageNumber);

  @override
  Future<BookPage> createPage(
    String bookId, {
    int? atNumber,
    String? heading,
  }) =>
      store.createPage(bookId, atNumber: atNumber, heading: heading);

  /// Throws StorageException(conflict) if the file changed outside the app or
  /// the page was renumbered since it was read. [force] overrides the first.
  @override
  Future<void> writePage(BookPage page, {bool force = false}) =>
      store.writePage(page, force: force);

  @override
  Future<void> deletePage(String bookId, int pageNumber) =>
      store.deletePage(bookId, pageNumber);
}

/// Everything wired up for main(): `final storage = await TxtStorage.open();`
class TxtStorage {
  TxtStorage._(this.platform, this.store)
      : books = TxtBookRepository(store, platform: platform),
        pages = TxtPageRepository(store);

  final StoragePlatform platform;
  final BookStore store;
  final TxtBookRepository books;
  final TxtPageRepository pages;

  static Future<TxtStorage> open({String? libraryRoot}) async {
    final platform = await StoragePlatform.create(libraryRoot: libraryRoot);
    final store = BookStore(
      backend: platform.backend,
      libraryRoot: platform.libraryRoot,
      onFolderReleased: platform.releaseFolder,
    );
    return TxtStorage._(platform, store);
  }
}
