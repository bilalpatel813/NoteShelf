// T5: T2 storage + T3 reader controller wired together through the real
// BookStoreReaderStorage adapter (no fakes). Plain dart:io, no plugins.
import 'dart:io';

import 'package:booknotes/core/contracts/contracts.dart';
import 'package:booknotes/data/storage/txt_repositories.dart';
import 'package:booknotes/features/bookshelf/bookshelf_providers.dart';
import 'package:booknotes/features/reader/reader_controller.dart';
import 'package:booknotes/features/reader/reader_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late String root;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('noteshelf_t5_');
    root = p.join(tmp.path, 'library');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('production providers have no demo defaults (missing override fails loudly)', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(() => c.read(bookRepositoryProvider), throwsA(anything));
    expect(() => c.read(bookshelfActionsProvider), throwsA(anything));
  });

  test('create, edit, autosave/flush, restart: book, text, typography and page persist', () async {
    var s = await TxtStorage.open(libraryRoot: root);
    final book = await s.books.createBook(
      const NewBookRequest(title: 'Journal'),
    );
    await s.pages.createPage(book.id); // 2 pages

    final c = ReaderController(
      book: book,
      storage: BookStoreReaderStorage(s.store),
      autosaveDelay: const Duration(hours: 1),
    );
    await c.open();
    c.bufferFor(1)!.text.text = 'hello world';
    await c.flush();
    expect(c.hasUnsavedChanges, isFalse);
    await c.setTypography(
      c.typography.copyWith(family: 'Merriweather', size: 24),
    );
    await c.goTo(2);
    expect(await c.close(), isTrue);
    c.dispose();

    // "Restart": a brand-new storage instance over the same folder.
    s = await TxtStorage.open(libraryRoot: root);
    final books = await s.books.listBooks();
    expect(books.map((b) => b.title), contains('Journal'));
    final again = books.firstWhere((b) => b.title == 'Journal');
    expect(again.id, book.id);
    expect(again.pageCount, 2);
    expect(again.lastOpenedPage, 2);
    expect((await s.pages.readPage(book.id, 1))!.content, 'hello world');
    final fonts = await s.store.getFontSettings(book.id);
    expect(fonts.family, 'Merriweather');
  });

  test('a failed save keeps the text in memory and the file on disk untouched', () async {
    final s = await TxtStorage.open(libraryRoot: root);
    final book = await s.books.createBook(const NewBookRequest(title: 'Safe'));
    final c = ReaderController(
      book: book,
      storage: BookStoreReaderStorage(s.store),
      autosaveDelay: const Duration(hours: 1),
    );
    await c.open();
    c.bufferFor(1)!.text.text = 'v1';
    await c.flush();

    // Change the file behind the app's back: the next save must not clobber it.
    final folder = Directory(book.folderRef);
    final file = folder.listSync().whereType<File>().firstWhere(
      (f) => f.path.toLowerCase().endsWith('.txt'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await file.writeAsString('edited elsewhere');

    c.bufferFor(1)!.text.text = 'v2 from app';
    await c.flush();
    expect(c.hasUnsavedChanges, isTrue); // not silently dropped
    expect(
      await file.readAsString(),
      'edited elsewhere',
    ); // not silently overwritten
    expect(c.bufferFor(1)!.text.text, 'v2 from app');
    c.dispose();
  });

  test('ZIP export then re-import preserves text and page count', () async {
    final s = await TxtStorage.open(libraryRoot: root);
    final book = await s.books.createBook(
      const NewBookRequest(title: 'Exported'),
    );
    await s.pages.createPage(book.id);
    final page = (await s.pages.readPage(book.id, 2))!;
    await s.pages.writePage(page.copyWith(content: 'second page text'));

    final zip = p.join(tmp.path, 'out.zip');
    await s.books.transfer.exportZipTo(book.id, zip);
    final imported = await s.books.transfer.importZipFrom(zip);

    expect(imported.id, isNot(book.id));
    expect(imported.pageCount, 2);
    expect(
      (await s.pages.readPage(imported.id, 2))!.content,
      'second page text',
    );
    // The original is untouched.
    expect((await s.pages.readPage(book.id, 2))!.content, 'second page text');
  });
}
