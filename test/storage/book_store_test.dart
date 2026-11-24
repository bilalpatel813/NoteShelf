// T2 storage tests. They use real temp directories through IoBackend; no
// Flutter plugins or devices are needed. Run: flutter test test/storage
//
// SAF (Android) is NOT covered here: it needs a device (see report).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:booknotes/core/contracts/contracts.dart';
import 'package:booknotes/core/models/book.dart';
import 'package:booknotes/data/storage/book_store.dart';
import 'package:booknotes/data/storage/book_transfer.dart';
import 'package:booknotes/data/storage/io_backend.dart';
import 'package:booknotes/data/storage/storage_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Wraps IoBackend and refuses access to chosen folders, like a revoked grant.
class FaultBackend implements StorageBackend {
  FaultBackend(this.inner);
  final StorageBackend inner;
  final denied = <String>{};

  void _gate(String ref) {
    if (denied.any((d) => ref == d || p.isWithin(d, ref))) {
      throw StorageException(
        StorageErrorKind.permissionDenied,
        'denied (test)',
        ref: ref,
      );
    }
  }

  @override
  Future<void> checkAccess(String r, {bool write = true}) async {
    _gate(r);
    return inner.checkAccess(r, write: write);
  }

  @override
  Future<String> displayName(String r) async {
    _gate(r);
    return inner.displayName(r);
  }

  @override
  Future<List<StorageEntry>> list(String r) async {
    _gate(r);
    return inner.list(r);
  }

  @override
  Future<StorageEntry?> stat(String r, String n) async {
    _gate(r);
    return inner.stat(r, n);
  }

  @override
  Future<Uint8List> readBytes(String r, String n) async {
    _gate(r);
    return inner.readBytes(r, n);
  }

  @override
  Future<StorageEntry> writeBytes(
    String r,
    String n,
    Uint8List b, {
    bool overwrite = false,
  }) async {
    _gate(r);
    return inner.writeBytes(r, n, b, overwrite: overwrite);
  }

  @override
  Future<void> delete(String r, String n) async {
    _gate(r);
    return inner.delete(r, n);
  }

  @override
  Future<void> rename(String r, String n, String nn) async {
    _gate(r);
    return inner.rename(r, n, nn);
  }

  @override
  Future<String> createFolder(String r, String n) async {
    _gate(r);
    return inner.createFolder(r, n);
  }

  @override
  Future<void> moveFolder(String r, String dp, String dn) async {
    _gate(r);
    return inner.moveFolder(r, dp, dn);
  }

  @override
  Future<void> deleteFolder(String r) async {
    _gate(r);
    return inner.deleteFolder(r);
  }

  @override
  Future<Uint8List> readDocument(String r) => inner.readDocument(r);

  @override
  Future<void> writeDocument(String r, Uint8List b, {bool overwrite = false}) =>
      inner.writeDocument(r, b, overwrite: overwrite);
}

void main() {
  late Directory tmp;
  final stores = <BookStore>[];

  Future<BookStore> openStore({StorageBackend? backend}) async {
    final s = BookStore(
      backend: backend ?? const IoBackend(),
      libraryRoot: p.join(tmp.path, 'BookNotes'),
    );
    stores.add(s);
    await s.ready;
    return s;
  }

  /// A plain folder of TXT files, like a user would have.
  Future<Directory> makeFolder(String name, Map<String, String> files) async {
    final d =
        await Directory(p.join(tmp.path, 'src', name)).create(recursive: true);
    for (final e in files.entries) {
      await File(p.join(d.path, e.key)).writeAsString(e.value);
    }
    return d;
  }

  List<String> txtNames(Directory d) => d
      .listSync()
      .map((e) => p.basename(e.path))
      .where((n) => n.endsWith('.txt'))
      .toList()
    ..sort(comparePageFileNames);

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('booknotes_t2_');
  });

  tearDown(() async {
    for (final s in stores) {
      await s.flush();
      await s.dispose();
    }
    stores.clear();
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  // ------------------------------------------------------------------ naming
  group('naming', () {
    test('sanitizeFileStem', () {
      expect(sanitizeFileStem('a<b>:c"/\\|?*d'), 'a b c d');
      expect(sanitizeFileStem('CON'), '_CON');
      expect(sanitizeFileStem('nul.txt'), '_nul.txt');
      expect(sanitizeFileStem('...'), 'Untitled');
      expect(sanitizeFileStem('  hi. '), 'hi');
      expect(sanitizeFileStem('x' * 100).length, 60);
    });

    test('parsePageFileName', () {
      ParsedPageName n(String f) => parsePageFileName(f);
      expect(n('Motion-001.txt').number, 1);
      expect(n('Motion-001.txt').heading, 'Motion');
      expect(n('01 Intro.txt').heading, 'Intro');
      expect(n('Page 2.txt').number, 2);
      expect(n('page10.txt').number, 10);
      expect(n('Plan-5-001.txt').heading, 'Plan-5');
      expect(n('Motion-001 (2).txt').number, 1);
      expect(n('notes.txt').number, isNull);
    });

    test('numeric order, not alphabetical (2 before 10)', () {
      final names = [
        'page 10.txt',
        'page 2.txt',
        'page 1.txt',
        'zeta.txt',
        'alpha.txt',
      ]..sort(comparePageFileNames);
      expect(names, [
        'page 1.txt',
        'page 2.txt',
        'page 10.txt',
        'alpha.txt',
        'zeta.txt',
      ]);
    });

    test('decodeText handles UTF-8 BOM, UTF-16 and legacy bytes', () {
      expect(
        decodeText(Uint8List.fromList([0xEF, 0xBB, 0xBF, 0x68, 0x69])),
        'hi',
      );
      expect(
        decodeText(Uint8List.fromList([0xFF, 0xFE, 0x68, 0x00, 0x69, 0x00])),
        'hi',
      );
      expect(
        decodeText(Uint8List.fromList([0x63, 0x61, 0x66, 0xE9])),
        'caf\u00E9',
      );
      expect(decodeText(encodeText('Ünï ✓')), 'Ünï ✓');
    });
  });

  // ------------------------------------------------------------------ create
  group('create book', () {
    test(
        'creates folder, metadata and first page; stream emits immediately and on change',
        () async {
      final s = await openStore();
      final emissions = <List<Book>>[];
      final sub = s.watchBooks().listen(emissions.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        emissions,
        isNotEmpty,
      ); // emitted the (empty) current list immediately
      expect(emissions.first, isEmpty);

      final book = await s.createBook(
        const NewBookRequest(title: 'Physics', subject: 'Science'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emissions.last.map((b) => b.title), ['Physics']);

      final dir = Directory(book.folderRef);
      expect(p.basename(dir.path), 'Physics');
      expect(File(p.join(dir.path, 'booknotes.json')).existsSync(), isTrue);
      expect(txtNames(dir), ['Page-001.txt']);
      expect(book.pageCount, 1);

      final meta = jsonDecode(
        File(p.join(dir.path, 'booknotes.json')).readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(meta['id'], book.id);
      expect((meta['pages'] as List).single['file'], 'Page-001.txt');
      await sub.cancel();
    });

    test('two books with the same title get distinct folders', () async {
      final s = await openStore();
      final a = await s.createBook(const NewBookRequest(title: 'Physics'));
      final b = await s.createBook(const NewBookRequest(title: 'Physics'));
      expect(a.id, isNot(b.id));
      expect(p.basename(a.folderRef), 'Physics');
      expect(p.basename(b.folderRef), 'Physics (2)');
    });

    test(
      'markOpened: page only changes when given; deleteBook moves to Trash',
      () async {
        final s = await openStore();
        final b = await s.createBook(const NewBookRequest(title: 'Opened'));
        await s.markOpened(b.id, page: 4);
        var cur = (await s.listBooks()).single;
        expect(cur.lastOpenedPage, 4);
        expect(cur.lastOpenedAt, isNotNull);
        await s.markOpened(b.id);
        cur = (await s.listBooks()).single;
        expect(cur.lastOpenedPage, 4);

        await s.deleteBook(b.id);
        expect(await s.listBooks(), isEmpty);
        expect(Directory(b.folderRef).existsSync(), isFalse);
        expect(Directory(s.trashRoot).listSync().length, 1);
      },
    );

    test('state survives a restart (registry + metadata)', () async {
      final s1 = await openStore();
      final b = await s1.createBook(
        const NewBookRequest(title: 'Persist', subject: 'X'),
      );
      await s1.createPage(b.id, heading: 'Second');
      await s1.markOpened(b.id, page: 2);
      await s1.flush();

      final s2 = await openStore();
      final list = await s2.listBooks();
      expect(list.single.id, b.id);
      expect(list.single.pageCount, 2);
      expect(list.single.lastOpenedPage, 2);
      expect((await s2.pageInfos(b.id)).map((i) => i.heading), [
        'Page',
        'Second',
      ]);
    });
  });

  // ------------------------------------------------------------------ import
  group('import folder', () {
    test(
        'copy mode: numeric order, original untouched, metadata created in the copy',
        () async {
      final src = await makeFolder('Notes', {
        'page 10.txt': 'ten',
        'page 2.txt': 'two',
        'page 1.txt': 'one',
        'readme.md': 'ignored',
      });
      final s = await openStore();
      final books = await s.importFolder(src.path);
      expect(books, hasLength(1));
      final b = books.single;
      expect(b.title, 'Notes');
      expect(b.pageCount, 3);
      expect(b.folderRef, isNot(src.path));

      final pages = await s.listPages(b.id, withContent: true);
      expect(pages.map((x) => x.content), ['one', 'two', 'ten']);
      expect(pages.map((x) => x.number), [1, 2, 3]);

      // original folder is exactly as the user left it
      expect(File(p.join(src.path, 'booknotes.json')).existsSync(), isFalse);
      expect(txtNames(src), ['page 1.txt', 'page 10.txt', 'page 2.txt']);
    });

    test(
        'importing the same folder twice never overwrites (second copy gets "(2)")',
        () async {
      final src = await makeFolder('Dup', {'a-001.txt': 'x'});
      final s = await openStore();
      final a = (await s.importFolder(src.path)).single;
      final b = (await s.importFolder(src.path)).single;
      expect(a.id, isNot(b.id));
      expect(p.basename(a.folderRef), 'Dup');
      expect(p.basename(b.folderRef), 'Dup (2)');
      expect(b.title, 'Dup'); // title comes from the source, not the suffix
    });

    test(
        'link mode: uses the folder in place, writes booknotes.json there, no duplicates',
        () async {
      final src = await makeFolder('Linked', {
        'Intro-001.txt': 'hello',
        'Next-002.txt': 'world',
      });
      final s = await openStore();
      final b = (await s.importFolder(src.path, mode: ImportMode.link)).single;
      expect(b.folderRef, src.path);
      expect(File(p.join(src.path, 'booknotes.json')).existsSync(), isTrue);

      await s.writePage(
        (await s.readPage(b.id, 1))!.copyWith(content: 'edited'),
      );
      expect(
        File(p.join(src.path, 'Intro-001.txt')).readAsStringSync(),
        'edited',
      );

      final again = (await s.importFolder(
        src.path,
        mode: ImportMode.link,
      ))
          .single;
      expect(again.id, b.id);
      expect(await s.listBooks(), hasLength(1));
    });

    test('a parent folder of several books imports each sub-folder', () async {
      await makeFolder('Library/Physics', {'a-001.txt': '1'});
      await makeFolder('Library/Chemistry', {'b-001.txt': '2'});
      await makeFolder('Library/Empty', {});
      final s = await openStore();
      final books = await s.importFolder(p.join(tmp.path, 'src', 'Library'));
      expect(books.map((b) => b.title).toSet(), {'Physics', 'Chemistry'});
    });

    test('a folder without TXT files is rejected', () async {
      final src = await makeFolder('Nothing', {'image.png': 'x'});
      final s = await openStore();
      expect(
        () => s.importFolder(src.path),
        throwsA(
          isA<StorageException>().having(
            (e) => e.kind,
            'kind',
            StorageErrorKind.invalidData,
          ),
        ),
      );
    });

    test(
      'an externally added TXT file is picked up and a deleted one dropped',
      () async {
        final src = await makeFolder('Live', {
          'a-001.txt': 'a',
          'b-002.txt': 'b',
        });
        final s = await openStore();
        final b = (await s.importFolder(
          src.path,
          mode: ImportMode.link,
        ))
            .single;
        File(p.join(src.path, 'c-003.txt')).writeAsStringSync('c');
        File(p.join(src.path, 'a-001.txt')).deleteSync();
        final infos = await s.pageInfos(b.id);
        expect(infos.map((i) => i.heading), ['b', 'c']);
      },
    );
  });

  // ------------------------------------------------------------------ pages
  group('pages', () {
    test('read, edit and save through the API', () async {
      final s = await openStore();
      final b = await s.createBook(const NewBookRequest(title: 'Edit'));
      final page = (await s.readPage(b.id, 1))!;
      expect(page.content, '');
      await s.writePage(page.copyWith(content: 'F = m a\nünïcode ✓'));
      final back = (await s.readPage(b.id, 1))!;
      expect(back.content, 'F = m a\nünïcode ✓');
      expect(
        File(p.join(b.folderRef, page.fileName)).readAsStringSync(),
        'F = m a\nünïcode ✓',
      );
      expect(await s.readPage(b.id, 2), isNull);
      expect(await s.readPage(b.id, 0), isNull);
    });

    test(
      'saving never overwrites an externally modified file unless forced',
      () async {
        final s = await openStore();
        final b = await s.createBook(const NewBookRequest(title: 'Conflict'));
        final page = (await s.readPage(b.id, 1))!;
        final f = File(p.join(b.folderRef, page.fileName));
        f.writeAsStringSync('changed elsewhere');
        f.setLastModifiedSync(DateTime.now().add(const Duration(minutes: 5)));

        await expectLater(
          s.writePage(page.copyWith(content: 'mine')),
          throwsA(
            isA<StorageException>().having(
              (e) => e.kind,
              'kind',
              StorageErrorKind.conflict,
            ),
          ),
        );
        expect(f.readAsStringSync(), 'changed elsewhere');

        await s.writePage(page.copyWith(content: 'mine'), force: true);
        expect(f.readAsStringSync(), 'mine');
      },
    );

    test(
      'consecutive saves of the same page do not conflict with themselves',
      () async {
        final s = await openStore();
        final b = await s.createBook(const NewBookRequest(title: 'Autosave'));
        final page = (await s.readPage(b.id, 1))!;
        await s.writePage(page.copyWith(content: 'one'));
        await s.writePage(page.copyWith(content: 'two'));
        expect((await s.readPage(b.id, 1))!.content, 'two');
      },
    );

    test('create in the middle renumbers files and keeps order', () async {
      final s = await openStore();
      final b = await s.createBook(const NewBookRequest(title: 'Order'));
      await s.writePage(
        (await s.readPage(b.id, 1))!.copyWith(content: 'first'),
      );
      await s.createPage(b.id, heading: 'Last'); // 2
      final mid = await s.createPage(b.id, atNumber: 2, heading: 'Middle');
      expect(mid.number, 2);

      final names = (await s.listPages(b.id)).map((x) => x.fileName).toList();
      expect(names, ['Page-001.txt', 'Middle-002.txt', 'Last-003.txt']);
      expect(txtNames(Directory(b.folderRef)), names);
      expect((await s.readPage(b.id, 1))!.content, 'first');
      expect((await s.listBooks()).single.pageCount, 3);
    });

    test('delete renumbers, move reorders, content follows its page', () async {
      final s = await openStore();
      final b = await s.createBook(const NewBookRequest(title: 'Shuffle'));
      for (final h in ['B', 'C', 'D']) {
        await s.createPage(b.id, heading: h);
      }
      for (var i = 1; i <= 4; i++) {
        final pg = (await s.readPage(b.id, i))!;
        await s.writePage(pg.copyWith(content: 'content $i'));
      }
      await s.deletePage(b.id, 2); // remove B
      expect((await s.listPages(b.id)).map((x) => x.fileName), [
        'Page-001.txt',
        'C-002.txt',
        'D-003.txt',
      ]);

      await s.movePage(b.id, 3, 1); // D to front
      final pages = await s.listPages(b.id, withContent: true);
      expect(pages.map((x) => x.fileName), [
        'D-001.txt',
        'Page-002.txt',
        'C-003.txt',
      ]);
      expect(pages.map((x) => x.content), [
        'content 4',
        'content 1',
        'content 3',
      ]);
      expect(txtNames(Directory(b.folderRef)), [
        'C-003.txt',
        'D-001.txt',
        'Page-002.txt',
      ]);
    });

    test(
      'rename heading renames the file safely and unusual names are sanitised',
      () async {
        final s = await openStore();
        final b = await s.createBook(const NewBookRequest(title: 'Rename'));
        await s.writePage(
          (await s.readPage(b.id, 1))!.copyWith(content: 'keep me'),
        );
        final renamed = await s.renamePage(b.id, 1, 'Motion: a/b?');
        expect(renamed.fileName, 'Motion a b-001.txt');
        expect((await s.readPage(b.id, 1))!.content, 'keep me');
        expect(
          (await s.pageInfos(b.id)).single.heading,
          'Motion: a/b?',
        ); // heading keeps the text

        final reserved = await s.renamePage(b.id, 1, 'CON');
        expect(reserved.fileName, '_CON-001.txt');
        expect(
          () => s.renamePage(b.id, 1, '   '),
          throwsA(
            isA<StorageException>().having(
              (e) => e.kind,
              'kind',
              StorageErrorKind.invalidName,
            ),
          ),
        );
      },
    );

    test(
      'same heading on several pages cannot collide (numbers differ)',
      () async {
        final s = await openStore();
        final b = await s.createBook(const NewBookRequest(title: 'Same'));
        await s.renamePage(b.id, 1, 'Notes');
        final second = await s.createPage(b.id, heading: 'Notes');
        expect(second.fileName, 'Notes-002.txt');
        expect(
          Directory(b.folderRef)
              .listSync()
              .where((e) => e.path.endsWith('.txt')),
          hasLength(2),
        );
      },
    );

    test('crash between renumber phases loses nothing', () async {
      final s1 = await openStore();
      final b = await s1.createBook(const NewBookRequest(title: 'Crash'));
      await s1.writePage(
        (await s1.readPage(b.id, 1))!.copyWith(content: 'survivor'),
      );
      await s1.flush();

      // Simulate a crash: file sits under its temp name, metadata names a
      // file that no longer exists.
      final meta = jsonDecode(
        File(p.join(b.folderRef, 'booknotes.json')).readAsStringSync(),
      ) as Map<String, dynamic>;
      final id = (meta['pages'] as List).single['id'] as String;
      File(p.join(b.folderRef, 'Page-001.txt'))
          .renameSync(p.join(b.folderRef, '.$id.bntmp'));

      final s2 = await openStore();
      final pages = await s2.listPages(b.id, withContent: true);
      expect(pages.single.content, 'survivor');
      expect(pages.single.fileName, 'Page-001.txt'); // normalised back
      expect(File(p.join(b.folderRef, 'Page-001.txt')).existsSync(), isTrue);
    });

    test(
      'corrupt booknotes.json is backed up and rebuilt from the folder',
      () async {
        final src = await makeFolder('Broken', {
          'a-001.txt': 'a',
          'b-002.txt': 'b',
        });
        final s = await openStore();
        final b = (await s.importFolder(
          src.path,
          mode: ImportMode.link,
        ))
            .single;
        File(p.join(src.path, 'booknotes.json'))
            .writeAsStringSync('{ not json');
        final s2 = await openStore();
        expect((await s2.pageInfos(b.id)).map((i) => i.heading), ['a', 'b']);
        expect(
          Directory(src.path)
              .listSync()
              .any((e) => p.basename(e.path).contains('.corrupt-')),
          isTrue,
        );
      },
    );

    test(
      'font settings and preferred reading mode persist in metadata',
      () async {
        final s = await openStore();
        final b = await s.createBook(const NewBookRequest(title: 'Fonts'));
        await s.setFontSettings(
          b.id,
          const FontSettings(family: 'Georgia', size: 22),
        );
        await s.updateBook(
          b.copyWith(preferredReadingMode: ReadingMode.twoPageSpread),
        );
        final s2 = await openStore();
        expect((await s2.getFontSettings(b.id)).family, 'Georgia');
        expect((await s2.getFontSettings(b.id)).size, 22);
        expect(
          (await s2.listBooks()).single.preferredReadingMode,
          ReadingMode.twoPageSpread,
        );
      },
    );
  });

  // ------------------------------------------------------------------ backend
  group('backend safety', () {
    test(
      'exclusive create refuses to overwrite; overwrite replaces atomically',
      () async {
        const io = IoBackend();
        await io.writeBytes(tmp.path, 'f.txt', encodeText('one'));
        await expectLater(
          io.writeBytes(tmp.path, 'f.txt', encodeText('two')),
          throwsA(
            isA<StorageException>().having(
              (e) => e.kind,
              'kind',
              StorageErrorKind.alreadyExists,
            ),
          ),
        );
        expect(File(p.join(tmp.path, 'f.txt')).readAsStringSync(), 'one');
        await io.writeBytes(
          tmp.path,
          'f.txt',
          encodeText('two'),
          overwrite: true,
        );
        expect(File(p.join(tmp.path, 'f.txt')).readAsStringSync(), 'two');
        expect(File(p.join(tmp.path, 'f.txt.bntmp')).existsSync(), isFalse);
      },
    );

    test(
        'rename and createFolder refuse existing targets; names cannot escape the folder',
        () async {
      const io = IoBackend();
      await io.writeBytes(tmp.path, 'a.txt', encodeText('a'));
      await io.writeBytes(tmp.path, 'b.txt', encodeText('b'));
      await expectLater(
        io.rename(tmp.path, 'a.txt', 'b.txt'),
        throwsA(isA<StorageException>()),
      );
      expect(File(p.join(tmp.path, 'b.txt')).readAsStringSync(), 'b');
      await io.createFolder(tmp.path, 'dir');
      await expectLater(
        io.createFolder(tmp.path, 'dir'),
        throwsA(isA<StorageException>()),
      );
      await expectLater(
        io.readBytes(tmp.path, '../x.txt'),
        throwsA(
          isA<StorageException>().having(
            (e) => e.kind,
            'kind',
            StorageErrorKind.invalidName,
          ),
        ),
      );
    });

    test(
      'checkAccess: missing folder -> notFound, file -> invalidData',
      () async {
        const io = IoBackend();
        await expectLater(
          io.checkAccess(p.join(tmp.path, 'nope')),
          throwsA(
            isA<StorageException>().having(
              (e) => e.kind,
              'kind',
              StorageErrorKind.notFound,
            ),
          ),
        );
        await File(p.join(tmp.path, 'f')).writeAsString('x');
        await expectLater(
          io.checkAccess(p.join(tmp.path, 'f')),
          throwsA(
            isA<StorageException>().having(
              (e) => e.kind,
              'kind',
              StorageErrorKind.invalidData,
            ),
          ),
        );
      },
    );
  });

  // ------------------------------------------------------------------ permissions
  group('permissions', () {
    test(
        'revoked folder: reads throw permissionDenied, shelf still shows the book, relink works',
        () async {
      final src = await makeFolder('Shared', {'a-001.txt': 'a'});
      final fault = FaultBackend(const IoBackend());
      final s = await openStore(backend: fault);
      final b = (await s.importFolder(src.path, mode: ImportMode.link)).single;
      expect(await s.checkBook(b.id), BookAccess.ok);

      fault.denied.add(src.path); // user revokes access

      expect(await s.checkBook(b.id), BookAccess.permissionDenied);
      await expectLater(
        s.listPages(b.id),
        throwsA(
          isA<StorageException>()
              .having((e) => e.kind, 'kind', StorageErrorKind.permissionDenied)
              .having((e) => e.needsReconnect, 'needsReconnect', isTrue),
        ),
      );
      await expectLater(
        s.writePage(BookPage(bookId: b.id, number: 1, fileName: 'a-001.txt')),
        throwsA(isA<StorageException>()),
      );
      // still listed, still openable on the shelf, last-opened still recorded
      expect((await s.listBooks()).single.title, 'Shared');
      await s.markOpened(b.id, page: 1);
      expect((await s.listBooks()).single.lastOpenedAt, isNotNull);

      // a different book's folder is refused
      final other = await makeFolder('Other', {'z-001.txt': 'z'});
      final otherBook = (await s.importFolder(
        other.path,
        mode: ImportMode.link,
      ))
          .single;
      expect(otherBook.id, isNot(b.id));
      await expectLater(
        s.relinkBook(b.id, other.path),
        throwsA(
          isA<StorageException>().having(
            (e) => e.kind,
            'kind',
            StorageErrorKind.invalidData,
          ),
        ),
      );

      fault.denied.clear(); // permission granted again via the picker
      final again = await s.relinkBook(b.id, src.path);
      expect(again.id, b.id);
      expect(await s.checkBook(b.id), BookAccess.ok);
      expect((await s.readPage(b.id, 1))!.content, 'a');
    });

    test(
      'link import of a folder that is not writable is refused (suggest copy)',
      () async {
        final src = await makeFolder('ReadOnly', {'a-001.txt': 'a'});
        final fault = FaultBackend(const IoBackend());
        final s = await openStore(backend: fault);
        // Reading allowed, writing not: emulate with a gate on write only.
        final wrapper = _ReadOnlyBackend(fault, src.path);
        final s2 = BookStore(
          backend: wrapper,
          libraryRoot: p.join(tmp.path, 'BookNotes2'),
        );
        stores.add(s2);
        await s2.ready;
        await expectLater(
          s2.importFolder(src.path, mode: ImportMode.link),
          throwsA(
            isA<StorageException>().having(
              (e) => e.kind,
              'kind',
              StorageErrorKind.permissionDenied,
            ),
          ),
        );
        // ...but copying the same folder works.
        expect((await s2.importFolder(src.path)).single.pageCount, 1);
        expect(s, isNotNull);
      },
    );

    test('deleting a linked book never touches the user\'s files', () async {
      final src = await makeFolder('Keep', {'a-001.txt': 'a'});
      final released = <String>[];
      final s = BookStore(
        backend: const IoBackend(),
        libraryRoot: p.join(tmp.path, 'BookNotes'),
        onFolderReleased: (r) async => released.add(r),
      );
      stores.add(s);
      await s.ready;
      final b = (await s.importFolder(src.path, mode: ImportMode.link)).single;
      await s.deleteBook(b.id);
      expect(File(p.join(src.path, 'a-001.txt')).readAsStringSync(), 'a');
      expect(released, [src.path]);
    });
  });

  // ------------------------------------------------------------------ export / import
  group('export and re-import', () {
    test('folder export is a normal folder and re-imports as a new book',
        () async {
      final s = await openStore();
      final b = await s.createBook(
        const NewBookRequest(title: 'Physics', subject: 'Science'),
      );
      await s.writePage(
        (await s.readPage(b.id, 1))!.copyWith(content: 'page one'),
      );
      await s.createPage(b.id, heading: 'Force');
      await s.writePage(
        (await s.readPage(b.id, 2))!.copyWith(content: 'page two'),
      );

      final out = await Directory(p.join(tmp.path, 'exports')).create();
      final t = BookTransfer(s);
      final ref = await t.exportFolder(b.id, out.path);
      expect(p.basename(ref), 'Physics');
      expect(txtNames(Directory(ref)), ['Force-002.txt', 'Page-001.txt']);
      expect(File(p.join(ref, 'booknotes.json')).existsSync(), isTrue);

      // exporting again never overwrites the first export
      final ref2 = await t.exportFolder(b.id, out.path);
      expect(p.basename(ref2), 'Physics (2)');

      // the exported folder is itself importable (id already exists -> new id)
      final imported = (await s.importFolder(ref)).single;
      expect(imported.id, isNot(b.id));
      expect(imported.title, 'Physics');
      final pages = await s.listPages(imported.id, withContent: true);
      expect(pages.map((x) => x.content), ['page one', 'page two']);
    });

    test(
      'ZIP export then import round-trips order, headings, content, settings',
      () async {
        final s = await openStore();
        final b = await s.createBook(
          const NewBookRequest(title: 'Zipped', subject: 'Maths'),
        );
        await s.setFontSettings(b.id, const FontSettings(size: 24));
        await s.writePage(
          (await s.readPage(b.id, 1))!.copyWith(content: 'alpha'),
        );
        await s.createPage(b.id, heading: 'Beta');
        await s.writePage(
          (await s.readPage(b.id, 2))!.copyWith(content: 'beta ✓'),
        );
        await s.movePage(b.id, 2, 1);

        final t = BookTransfer(s);
        final target = p.join(tmp.path, 'Zipped.zip');
        await t.exportZipTo(b.id, target);
        expect(File(target).existsSync(), isTrue);
        await expectLater(
          t.exportZipTo(b.id, target), // would overwrite
          throwsA(
            isA<StorageException>().having(
              (e) => e.kind,
              'kind',
              StorageErrorKind.alreadyExists,
            ),
          ),
        );

        final names = ZipDecoder()
            .decodeBytes(File(target).readAsBytesSync())
            .files
            .map((f) => f.name)
            .toList();
        expect(
          names,
          containsAll([
            'Zipped/booknotes.json',
            'Zipped/Beta-001.txt',
            'Zipped/Page-002.txt',
          ]),
        );

        final copy = await t.importZipFrom(target);
        expect(copy.id, isNot(b.id)); // original untouched
        expect(copy.title, 'Zipped');
        expect(copy.subject, 'Maths');
        expect(p.basename(copy.folderRef), 'Zipped (2)');
        final pages = await s.listPages(copy.id, withContent: true);
        expect(pages.map((x) => x.fileName), ['Beta-001.txt', 'Page-002.txt']);
        expect(pages.map((x) => x.content), ['beta ✓', 'alpha']);
        expect((await s.getFontSettings(copy.id)).size, 24);
        expect((await s.listBooks()), hasLength(2));
      },
    );

    test(
      'a plain ZIP of TXT files imports; hostile ZIPs are rejected',
      () async {
        final s = await openStore();
        final t = BookTransfer(s);

        Uint8List zip(Map<String, String> files) {
          final a = Archive();
          files.forEach((n, c) {
            final bytes = utf8.encode(c);
            a.addFile(ArchiveFile(n, bytes.length, bytes));
          });
          return Uint8List.fromList(ZipEncoder().encode(a)!);
        }

        final plain = await t.importZipBytes(
          zip({
            'Chem/p2.txt': 'two',
            'Chem/p10.txt': 'ten',
            'Chem/p1.txt': 'one',
          }),
        );
        expect(plain.title, 'Chem');
        expect(
          (await s.listPages(
            plain.id,
            withContent: true,
          ))
              .map((x) => x.content),
          ['one', 'two', 'ten'],
        );

        for (final evil in [
          {'../evil.txt': 'x'},
          {'/abs/evil.txt': 'x'},
          {'C:/evil.txt': 'x'},
          {'ok/../../evil.txt': 'x'},
        ]) {
          await expectLater(
            t.importZipBytes(zip(evil)),
            throwsA(
              isA<StorageException>().having(
                (e) => e.kind,
                'kind',
                StorageErrorKind.invalidData,
              ),
            ),
          );
        }
        await expectLater(
          t.importZipBytes(zip({'readme.md': 'no pages'})),
          throwsA(isA<StorageException>()),
        );
        await expectLater(
          t.importZipBytes(Uint8List.fromList([1, 2, 3])),
          throwsA(isA<StorageException>()),
        );
        // nothing was written outside the library, and failed imports left no folders behind
        expect(File(p.join(tmp.path, 'evil.txt')).existsSync(), isFalse);
        expect(Directory(s.booksRoot).listSync().length, 1);
      },
    );
  });
}

/// Reads fine, but any write inside [root] is denied (e.g. a read-only share).
class _ReadOnlyBackend extends FaultBackend {
  _ReadOnlyBackend(super.inner, this.root);
  final String root;

  bool _in(String r) => r == root || p.isWithin(root, r);

  @override
  Future<void> checkAccess(String r, {bool write = true}) async {
    if (write && _in(r)) {
      throw StorageException(
        StorageErrorKind.permissionDenied,
        'read-only (test)',
        ref: r,
      );
    }
    return super.checkAccess(r, write: write);
  }

  @override
  Future<StorageEntry> writeBytes(
    String r,
    String n,
    Uint8List b, {
    bool overwrite = false,
  }) async {
    if (_in(r)) {
      throw StorageException(
        StorageErrorKind.permissionDenied,
        'read-only (test)',
        ref: r,
      );
    }
    return super.writeBytes(r, n, b, overwrite: overwrite);
  }
}
