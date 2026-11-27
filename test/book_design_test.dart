import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:booknotes/core/contracts/contracts.dart';
import 'package:booknotes/core/models/book.dart';
import 'package:booknotes/core/models/book_design.dart';
import 'package:booknotes/core/theme/book_visuals.dart';
import 'package:booknotes/data/storage/book_store.dart';
import 'package:booknotes/data/storage/book_transfer.dart';
import 'package:booknotes/data/storage/io_backend.dart';
import 'package:booknotes/features/bookshelf/book_card.dart';
import 'package:booknotes/features/bookshelf/cover_editor.dart';
import 'package:booknotes/features/reader/reader_controller.dart';
import 'package:booknotes/features/reader/reader_models.dart';
import 'package:booknotes/features/reader/reader_page_surface.dart';
import 'package:booknotes/features/reader/reader_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'reader/reader_test.dart' show FakeStorage;

const book = Book(
  id: 'id',
  title: 'A book',
  subject: 'Notes',
  folderRef: '/book',
);

void main() {
  test('legacy covers and unknown design values have safe defaults', () {
    expect(BookCoverRef.fromJson({'colorValue': 0xFF123456}).design, isNull);
    final design = BookDesign.fromJson({
      'theme': 'future',
      'icon': 7,
      'bookmark': 'yes',
    });
    expect(design.theme, BookTheme.basic);
    expect(design.icon, CoverIcon.none);
    expect(design.bookmark, false);
    for (final theme in BookTheme.values) {
      final preset = BookDesign.preset(theme);
      final changed = preset.copyWith(
        author: 'Author',
        bookmark: !preset.bookmark,
      );
      expect(BookDesign.fromJson(changed.toJson()).toJson(), changed.toJson());
      expect(BookDesign.preset(theme).author, isEmpty);
    }
  });

  test(
    'design and artwork survive update, reopen and page operations',
    () async {
      final temp = await Directory.systemTemp.createTemp('design-test-');
      final root = p.join(temp.path, 'library');
      BookStore? store;
      try {
        store = BookStore(backend: const IoBackend(), libraryRoot: root);
        await store.ready;
        final created = await store.createBook(
          const NewBookRequest(title: 'Original', subject: 'Notes'),
        );
        final image = File(p.join(temp.path, 'art.png'));
        await image.writeAsBytes([1, 2, 3]);
        final design = BookDesign.preset(BookTheme.minecraft)
            .copyWith(subtitle: 'Sub', author: 'Writer', bookmark: true);
        await store.updateBook(
          created.copyWith(
            title: 'Updated',
            cover: BookCoverRef(
              imagePath: image.path,
              colorValue: 0xFF123456,
              design: design,
            ),
          ),
        );
        await store.createPage(created.id);
        final saved = (await store.listBooks()).single;
        expect(saved.cover.imagePath, isNotNull);
        expect(saved.cover.imagePath, isNot(image.path));
        final meta = jsonDecode(
          await File(p.join(saved.folderRef, 'booknotes.json')).readAsString(),
        ) as Map;
        expect(
          (meta['cover'] as Map)['imagePath'],
          p.basename(saved.cover.imagePath!),
        );
        expect(((meta['cover'] as Map)['design'] as Map)['theme'], 'minecraft');
        await store.flush();
        await store.dispose();
        store = BookStore(backend: const IoBackend(), libraryRoot: root);
        await store.ready;
        await store.flush();
        final reopened = (await store.listBooks()).single;
        expect(reopened.title, 'Updated');
        expect(reopened.cover.design!.toJson(), design.toJson());
        expect(await File(reopened.cover.imagePath!).readAsBytes(), [1, 2, 3]);
        expect((await store.listPages(created.id)).length, 2);
        final transfer = BookTransfer(store);
        final zip = p.join(temp.path, 'book.zip');
        await transfer.exportZipTo(created.id, zip);
        final imported = await transfer.importZipFrom(zip);
        expect(imported.cover.design!.toJson(), design.toJson());
        expect(await File(imported.cover.imagePath!).readAsBytes(), [1, 2, 3]);
        await expectLater(
          store.updateBook(
            reopened.copyWith(
              cover: BookCoverRef(
                imagePath: p.join(temp.path, 'missing.png'),
                design: design,
              ),
            ),
          ),
          throwsA(isA<Exception>()),
        );
        expect(
          (await store.listBooks()).first.cover.imagePath,
          reopened.cover.imagePath,
        );
        await store.updateBook(
          reopened.copyWith(
            cover: BookCoverRef(
              colorValue: reopened.cover.colorValue,
              design: design,
            ),
          ),
        );
        expect((await store.listBooks()).first.cover.imagePath, isNull);
      } finally {
        await store?.flush();
        await store?.dispose();
        await temp.delete(recursive: true);
      }
    },
  );

  testWidgets('all designs render as closed, single and two-page books', (
    tester,
  ) async {
    for (final theme in BookTheme.values) {
      final designed = book.copyWith(
        cover: BookCoverRef(design: BookDesign.preset(theme)),
      );
      final controller = ReaderController(
        book: designed,
        storage: FakeStorage(2),
      );
      await controller.open();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(
                  width: 120,
                  height: 180,
                  child: BookCoverView(book: designed, width: 120),
                ),
                Expanded(child: SpreadView(controller: controller, anchor: 1)),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(DesignedBookCover), findsOneWidget);
      expect(find.byType(BookPageSurface), findsOneWidget);
      expect(
        tester
            .widget<BookPageSurface>(find.byType(BookPageSurface))
            .design!
            .theme,
        theme,
      );
      controller.layout = ReaderLayout.unfolded;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SpreadView(controller: controller, anchor: 1)),
        ),
      );
      expect(find.byType(BookPageSurface), findsNWidgets(2));
      final pages = tester
          .widgetList<ReaderPageSurface>(find.byType(ReaderPageSurface))
          .toList();
      expect(pages.map((page) => page.design!.theme), [theme, theme]);
      expect(pages.map((page) => page.leftSide), [true, false]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    }
  });

  testWidgets(
    'editor saves independent choices and cancel leaves book unchanged',
    (tester) async {
      Book? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showDialog<Book>(
                    context: context,
                    builder: (_) => const CoverEditor(book: book),
                  );
                },
                child: const Text('Edit'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'New title',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Subtitle'),
        'New subtitle',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Author'),
        'New author',
      );
      await tester.ensureVisible(find.text('Theme'));
      await tester.tap(find.text('Basic').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Diary').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(result!.title, 'New title');
      expect(result!.cover.design!.theme, BookTheme.diary);
      expect(result!.cover.design!.subtitle, 'New subtitle');
      expect(result!.cover.design!.author, 'New author');
      expect(book.cover.design, isNull);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'Discard',
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    },
  );

  testWidgets('editor remains usable on a narrow screen with enlarged text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final longBook = book.copyWith(
      title: 'A very long title that must fit inside a small cover preview',
      cover: BookCoverRef(
        design: BookDesign.preset(BookTheme.medieval).copyWith(
          subtitle: 'A long subtitle for the preview',
          author: 'An author with a long name',
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 600),
            textScaler: TextScaler.linear(1.5),
          ),
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => CoverEditor(book: longBook),
                ),
                child: const Text('Edit'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'preset changes update controls and retain book metadata and artwork',
    (tester) async {
      final original = book.copyWith(
        cover: BookCoverRef(
          imagePath: '/missing/cover.png',
          design: BookDesign.preset(BookTheme.medieval)
              .copyWith(subtitle: 'Subtitle', author: 'Writer'),
        ),
        pageCount: 7,
        lastOpenedPage: 3,
        preferredReadingMode: ReadingMode.twoPageSpread,
      );
      Book? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => result = await showDialog<Book>(
                  context: context,
                  builder: (_) => CoverEditor(book: original),
                ),
                child: const Text('Edit'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DesignedBookCover), findsOneWidget);
      await tester.ensureVisible(find.text('Theme'));
      await tester.tap(find.text('Medieval').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Diary').last);
      await tester.pumpAndSettle();
      final icon = tester.state<FormFieldState<CoverIcon>>(
        find.byType(DropdownButtonFormField<CoverIcon>),
      );
      final decoration = tester.state<FormFieldState<CoverDecoration>>(
        find.byType(DropdownButtonFormField<CoverDecoration>),
      );
      final texture = tester.state<FormFieldState<BookTexture>>(
        find.byType(DropdownButtonFormField<BookTexture>),
      );
      expect(icon.value, CoverIcon.flower);
      expect(decoration.value, CoverDecoration.frame);
      expect(texture.value, BookTexture.ruled);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(result!.cover.imagePath, original.cover.imagePath);
      expect(result!.cover.design!.subtitle, 'Subtitle');
      expect(result!.cover.design!.author, 'Writer');
      expect(result!.cover.design!.bookmark, true);
      expect(result!.subject, original.subject);
      expect(result!.pageCount, 7);
      expect(result!.lastOpenedPage, 3);
      expect(result!.preferredReadingMode, ReadingMode.twoPageSpread);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Use generated cover'));
      await tester.tap(find.text('Use generated cover'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(result!.cover.imagePath, isNull);
      expect(original.cover.imagePath, '/missing/cover.png');
    },
  );

  testWidgets('artwork picker retains the old image on cancel and failure', (
    tester,
  ) async {
    final original = book.copyWith(
      cover: const BookCoverRef(imagePath: '/missing/cover.png'),
    );
    final pending = Completer<String?>();
    var calls = 0;
    Book? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => result = await showDialog<Book>(
                context: context,
                builder: (_) => CoverEditor(
                  book: original,
                  pickImage: () {
                    calls++;
                    if (calls == 1) return pending.future;
                    return Future<String?>.error('picker failed');
                  },
                ),
              ),
              child: const Text('Edit'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Choose artwork'));
    await tester.tap(find.text('Choose artwork'));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNull,
    );
    pending.complete(null);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose artwork'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not choose artwork'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Title'))
          .decoration!
          .errorText,
      isNull,
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result!.cover.imagePath, original.cover.imagePath);
  });
}
