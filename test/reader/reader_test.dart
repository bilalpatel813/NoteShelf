// T3 reader tests. No device or plugins needed: `flutter test test/reader`.
import 'package:booknotes/core/models/book.dart';
import 'package:booknotes/data/storage/book_store.dart'
    show FontSettings, PageInfo;
import 'package:booknotes/data/storage/storage_backend.dart';
import 'package:booknotes/features/reader/reader_controller.dart';
import 'package:booknotes/features/reader/reader_models.dart';
import 'package:booknotes/features/reader/reader_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _P {
  _P(this.id, this.heading, this.text);
  final String id;
  String heading;
  String text;
}

/// In-memory ReaderStorage that mimics T2: renumbering changes file names.
class FakeStorage implements ReaderStorage {
  FakeStorage(int n) {
    for (var i = 1; i <= n; i++) {
      pages.add(_P('id$i', 'Page', 'text $i'));
    }
  }

  final pages = <_P>[];
  var fonts = const FontSettings();
  int? lastOpenedPage;
  Object? failWrite; // thrown by writePage while set
  final writes = <String>[];
  var _next = 100;

  String _name(int i) =>
      '${pages[i].heading}-${(i + 1).toString().padLeft(3, '0')}.txt';

  @override
  Future<List<PageInfo>> pageInfos(String bookId) async => [
        for (var i = 0; i < pages.length; i++)
          PageInfo(
            id: pages[i].id,
            number: i + 1,
            fileName: _name(i),
            heading: pages[i].heading,
          ),
      ];

  @override
  Future<BookPage?> readPage(String bookId, int n) async =>
      n < 1 || n > pages.length
          ? null
          : BookPage(
              bookId: bookId,
              number: n,
              fileName: _name(n - 1),
              content: pages[n - 1].text,
            );

  @override
  Future<BookPage> createPage(String bookId, {int? atNumber}) async {
    final at = (atNumber ?? pages.length + 1).clamp(1, pages.length + 1);
    pages.insert(at - 1, _P('id${_next++}', 'Page', ''));
    return BookPage(bookId: bookId, number: at, fileName: _name(at - 1));
  }

  @override
  Future<void> writePage(BookPage page, {bool force = false}) async {
    final f = failWrite;
    if (f != null) throw f;
    final i = [for (var k = 0; k < pages.length; k++) _name(k)]
        .indexOf(page.fileName);
    if (i < 0) {
      throw const StorageException(StorageErrorKind.conflict, 'renumbered');
    }
    pages[i].text = page.content;
    writes.add('${page.fileName}=${page.content}');
  }

  @override
  Future<void> deletePage(String bookId, int n) async => pages.removeAt(n - 1);

  @override
  Future<BookPage> renamePage(String bookId, int n, String heading) async {
    pages[n - 1].heading = heading;
    return BookPage(bookId: bookId, number: n, fileName: _name(n - 1));
  }

  @override
  Future<FontSettings> getFontSettings(String bookId) async => fonts;
  @override
  Future<void> setFontSettings(String bookId, FontSettings f) async =>
      fonts = f;
  @override
  Future<void> markOpened(String bookId, {int? page}) async =>
      lastOpenedPage = page;
}

Book _book({int last = 1, ReadingMode mode = ReadingMode.singlePage}) => Book(
      id: 'b1',
      title: 'Physics',
      subject: 'Science',
      folderRef: '/x',
      lastOpenedPage: last,
      preferredReadingMode: mode,
    );

Future<ReaderController> _open(
  FakeStorage s, {
  Book? book,
  Duration delay = const Duration(milliseconds: 20),
}) async {
  final c = ReaderController(
    book: book ?? _book(),
    storage: s,
    autosaveDelay: delay,
  );
  await c.open();
  return c;
}

void main() {
  group('SpreadMath', () {
    test('folded shows one page', () {
      expect(SpreadMath.spreadFor(3, 5, ReaderLayout.folded), const Spread(3));
    });
    test(
      'unfolded pairs (1,2)(3,4) and anchors even pages to the odd left page',
      () {
        expect(
          SpreadMath.spreadFor(1, 6, ReaderLayout.unfolded),
          const Spread(1, 2),
        );
        expect(
          SpreadMath.spreadFor(4, 6, ReaderLayout.unfolded),
          const Spread(3, 4),
        );
      },
    );
    test('odd final page has no right page', () {
      expect(
        SpreadMath.spreadFor(5, 5, ReaderLayout.unfolded),
        const Spread(5, null),
      );
      expect(SpreadMath.label(const Spread(5), 5), 'Page 5 of 5');
      expect(SpreadMath.label(const Spread(3, 4), 5), 'Pages 3\u20134 of 5');
    });
    test('move is clamped and respects spreads', () {
      expect(SpreadMath.move(1, 1, 5, ReaderLayout.unfolded), 3);
      expect(SpreadMath.move(5, 1, 5, ReaderLayout.unfolded), 5);
      expect(SpreadMath.move(1, -1, 5, ReaderLayout.unfolded), 1);
      expect(SpreadMath.canGoForward(3, 5, ReaderLayout.unfolded), isTrue);
      expect(SpreadMath.canGoForward(5, 5, ReaderLayout.unfolded), isFalse);
      expect(SpreadMath.canGoForward(4, 4, ReaderLayout.unfolded), isFalse);
    });
  });

  group('TypographySettings', () {
    test('round-trips through T2 FontSettings JSON', () {
      const t = TypographySettings(
        family: 'Lora',
        size: 22,
        weight: 700,
        lineHeight: 1.8,
        paragraphSpacing: 12,
        align: TextAlign.justify,
        color: Color(0xFF1F3A5F),
      );
      final back = TypographySettings.fromStored(
        FontSettings.fromJson(t.toStored().toJson()),
      );
      expect(back, t);
    });
    test('old settings files (family/size/lineHeight only) still load', () {
      final t = TypographySettings.fromStored(
        FontSettings.fromJson({
          'family': 'Arial',
          'size': 20,
          'lineHeight': 1.4,
        }),
      );
      expect(t.family, 'Arial');
      expect(t.weight, 400);
      expect(t.align, TextAlign.left);
      expect(t.color, isNull);
    });
    test('values are clamped', () {
      final t = const TypographySettings().copyWith(size: 999, lineHeight: 0);
      expect(t.size, TypographySettings.maxSize);
      expect(t.lineHeight, TypographySettings.minLineHeight);
    });
  });

  group('ReaderController', () {
    test(
      'opens in Edit mode on the last opened page with stored typography',
      () async {
        final s = FakeStorage(5)
          ..fonts = const FontSettings(family: 'Lora', size: 24, weight: 600);
        final c = await _open(s, book: _book(last: 3));
        expect(c.mode, ReaderMode.edit);
        expect(c.currentPage, 3);
        expect(c.typography.family, 'Lora');
        expect(c.typography.size, 24);
        expect(c.typography.weight, 600);
        expect(c.bufferFor(3)!.text.text, 'text 3');
        c.dispose();
      },
    );

    test(
      'twoPageSpread preference opens unfolded and loads both pages',
      () async {
        final s = FakeStorage(5);
        final c = await _open(
          s,
          book: _book(last: 4, mode: ReadingMode.twoPageSpread),
        );
        expect(c.layout, ReaderLayout.unfolded);
        expect(c.spread, const Spread(3, 4));
        expect(c.bufferFor(3)!.loaded && c.bufferFor(4)!.loaded, isTrue);
        c.dispose();
      },
    );

    test('last page out of range is clamped', () async {
      final c = await _open(FakeStorage(2), book: _book(last: 99));
      expect(c.currentPage, 2);
      c.dispose();
    });

    test(
      'typed text survives navigating away and back, before any save',
      () async {
        final s = FakeStorage(3);
        final c = await _open(s, delay: const Duration(hours: 1));
        c.bufferFor(1)!.text.text = 'my edit';
        await c.next();
        await c.next();
        await c.previous();
        await c.previous();
        expect(c.bufferFor(1)!.text.text, 'my edit');
        expect(c.hasUnsavedChanges, isTrue);
        expect(s.pages[0].text, 'text 1'); // disk untouched until flush
        c.dispose();
      },
    );

    test('autosave writes after the delay and marks saved', () async {
      final s = FakeStorage(2);
      final c = await _open(s, delay: const Duration(milliseconds: 30));
      c.bufferFor(1)!.text.text = 'auto';
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(s.pages[0].text, 'auto');
      expect(c.overallStatus, SaveStatus.saved);
      c.dispose();
    });

    test('save error keeps the text dirty and retry succeeds', () async {
      final s = FakeStorage(2);
      final c = await _open(s, delay: const Duration(hours: 1));
      c.bufferFor(1)!.text.text = 'precious';
      s.failWrite = const StorageException(StorageErrorKind.io, 'disk full');
      expect(await c.flush(), isFalse);
      expect(c.overallStatus, SaveStatus.error);
      expect(c.bufferFor(1)!.text.text, 'precious');
      s.failWrite = null;
      expect(await c.retrySave(), isTrue);
      expect(s.pages[0].text, 'precious');
      expect(c.overallStatus, SaveStatus.saved);
      c.dispose();
    });

    test('conflict is not retried silently; overwrite resolves it', () async {
      final s = FakeStorage(1);
      final c = await _open(s, delay: const Duration(hours: 1));
      c.bufferFor(1)!.text.text = 'mine';
      s.failWrite = const StorageException(
        StorageErrorKind.conflict,
        'changed outside',
      );
      expect(await c.flush(), isFalse);
      expect(c.bufferFor(1)!.conflict, isTrue);
      s.failWrite = null;
      expect(await c.flush(), isFalse); // still needs an explicit decision
      expect(await c.overwriteConflicts(), isTrue);
      expect(s.pages[0].text, 'mine');
      c.dispose();
    });

    test(
      'addPage flushes dirty text first, renumbers and opens the new page',
      () async {
        final s = FakeStorage(3);
        final c = await _open(s, delay: const Duration(hours: 1));
        c.bufferFor(1)!.text.text = 'before add';
        expect(await c.addPage(), isTrue);
        expect(s.pages[0].text, 'before add');
        expect(c.pageCount, 4);
        expect(c.currentPage, 2);
        expect(c.bufferFor(2)!.text.text, '');
        expect(
          c.bufferFor(3)!.id,
          'id2',
        ); // old page 2 moved, kept its identity
        c.dispose();
      },
    );

    test('addPage is aborted and text kept when the flush fails', () async {
      final s = FakeStorage(2);
      final c = await _open(s, delay: const Duration(hours: 1));
      c.bufferFor(1)!.text.text = 'keep me';
      s.failWrite = const StorageException(StorageErrorKind.io, 'boom');
      expect(await c.addPage(), isFalse);
      expect(s.pages.length, 2);
      expect(c.bufferFor(1)!.text.text, 'keep me');
      expect(c.operationError, isNotNull);
      c.dispose();
    });

    test('unsaved text on other pages survives deleting a page', () async {
      final s = FakeStorage(3);
      final c = await _open(s, delay: const Duration(hours: 1));
      await c.goTo(3);
      c.bufferFor(3)!.text.text = 'page three edit';
      expect(await c.deletePage(1), isTrue);
      expect(c.pageCount, 2);
      expect(c.bufferFor(2)!.text.text, 'page three edit');
      expect(s.pages[1].text, 'page three edit');
      c.dispose();
    });

    test('the last remaining page cannot be deleted', () async {
      final s = FakeStorage(1);
      final c = await _open(s);
      expect(await c.deletePage(1), isFalse);
      expect(s.pages.length, 1);
      c.dispose();
    });

    test('rename heading saves text first and keeps it', () async {
      final s = FakeStorage(2);
      final c = await _open(s, delay: const Duration(hours: 1));
      c.bufferFor(1)!.text.text = 'kept';
      expect(await c.renameHeading(1, 'Motion'), isTrue);
      expect(c.bufferFor(1)!.heading, 'Motion');
      expect(s.pages[0].text, 'kept');
      expect(await c.flush(), isTrue);
      c.dispose();
    });

    test(
      'switching to View mode saves; typography never touches TXT',
      () async {
        final s = FakeStorage(2);
        final c = await _open(s, delay: const Duration(hours: 1));
        c.bufferFor(1)!.text.text = 'edited';
        c.setMode(ReaderMode.view);
        await c.flush();
        expect(s.pages[0].text, 'edited');
        await c.setTypography(
          c.typography.copyWith(
            family: 'Merriweather',
            size: 30,
            align: TextAlign.center,
          ),
        );
        expect(s.pages[0].text, 'edited');
        expect(s.fonts.family, 'Merriweather');
        expect(s.fonts.align, 'center');
        c.dispose();
      },
    );

    test('layout switch keeps position on an anchor and loads pages', () async {
      final s = FakeStorage(5);
      final c = await _open(s);
      await c.goTo(4);
      await c.setLayout(ReaderLayout.unfolded);
      expect(c.spread, const Spread(3, 4));
      await c.goTo(5);
      expect(c.spread, const Spread(5, null));
      await c.setLayout(ReaderLayout.folded);
      expect(c.currentPage, 5);
      c.dispose();
    });

    test(
      'close records the page and discardUnsaved restores saved text',
      () async {
        final s = FakeStorage(3);
        final c = await _open(s, delay: const Duration(hours: 1));
        await c.goTo(2);
        expect(await c.close(), isTrue);
        expect(s.lastOpenedPage, 2);
        c.bufferFor(2)!.text.text = 'oops';
        c.discardUnsaved();
        expect(c.bufferFor(2)!.text.text, 'text 2');
        expect(c.hasUnsavedChanges, isFalse);
        c.dispose();
      },
    );
  });

  group('ReaderScreen widgets', () {
    Future<void> pump(WidgetTester t, FakeStorage s, {Book? book}) async {
      t.view.physicalSize = const Size(1400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            book: book ?? _book(),
            storage: s,
            autosaveDelay: const Duration(hours: 1),
          ),
        ),
      );
      await t.pumpAndSettle();
    }

    testWidgets('edit mode shows editor + controls; view mode hides them', (
      t,
    ) async {
      final s = FakeStorage(3);
      await pump(t, s);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byTooltip('Add page'), findsOneWidget);
      expect(find.byTooltip('Delete this page'), findsOneWidget);
      expect(find.text('Page 1 of 3'), findsOneWidget);

      await t.tap(find.byTooltip('Switch to View mode (Ctrl+E)'));
      await t.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.byTooltip('Add page'), findsNothing);
      expect(find.byTooltip('Delete this page'), findsNothing);
      expect(find.text('text 1'), findsOneWidget);
      // navigation still works
      await t.tap(find.byTooltip('Next (Alt+Right)'));
      await t.pumpAndSettle();
      expect(find.text('text 2'), findsOneWidget);
    });

    testWidgets('typing, paging away and back keeps the text', (t) async {
      final s = FakeStorage(3);
      await pump(t, s);
      await t.enterText(find.byType(TextField), 'hello world');
      await t.pump();
      await t.tap(find.byTooltip('Next (Alt+Right)'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Previous (Alt+Left)'));
      await t.pumpAndSettle();
      expect(find.text('hello world'), findsOneWidget);
    });

    testWidgets(
      'unfolded shows two pages and a blank right side on an odd last page',
      (t) async {
        final s = FakeStorage(3);
        await pump(t, s, book: _book(mode: ReadingMode.twoPageSpread));
        expect(find.text('Pages 1\u20132 of 3'), findsOneWidget);
        expect(find.byType(TextField), findsNWidgets(2));
        await t.tap(find.byTooltip('Next (Alt+Right)'));
        await t.pumpAndSettle();
        expect(find.text('Page 3 of 3'), findsOneWidget);
        expect(find.byType(TextField), findsOneWidget);
      },
    );
  });
}
