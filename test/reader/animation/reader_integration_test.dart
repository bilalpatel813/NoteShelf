// T4 integration: the animators inside the real T3 ReaderScreen / BookReaderView.
import 'package:booknotes/core/models/book.dart';
import 'package:booknotes/data/storage/book_store.dart' show FontSettings, PageInfo;
import 'package:booknotes/features/reader/animation/page_turn_animator.dart';
import 'package:booknotes/features/reader/reader_controller.dart';
import 'package:booknotes/features/reader/reader_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal in-memory ReaderStorage: [n] pages with text "text 1".."text n".
class _Storage implements ReaderStorage {
  _Storage(this.n);
  final int n;
  var fonts = const FontSettings();

  String _name(int i) => 'Page-${i.toString().padLeft(3, '0')}.txt';

  @override
  Future<List<PageInfo>> pageInfos(String bookId) async => [
    for (var i = 1; i <= n; i++)
      PageInfo(id: 'id$i', number: i, fileName: _name(i), heading: 'Page'),
  ];
  @override
  Future<BookPage?> readPage(String bookId, int p) async => p < 1 || p > n
      ? null
      : BookPage(bookId: bookId, number: p, fileName: _name(p), content: 'text $p');
  @override
  Future<BookPage> createPage(String bookId, {int? atNumber}) async =>
      BookPage(bookId: bookId, number: n + 1, fileName: _name(n + 1));
  @override
  Future<void> writePage(BookPage page, {bool force = false}) async {}
  @override
  Future<void> deletePage(String bookId, int p) async {}
  @override
  Future<BookPage> renamePage(String bookId, int p, String heading) async =>
      BookPage(bookId: bookId, number: p, fileName: _name(p));
  @override
  Future<FontSettings> getFontSettings(String bookId) async => fonts;
  @override
  Future<void> setFontSettings(String bookId, FontSettings f) async => fonts = f;
  @override
  Future<void> markOpened(String bookId, {int? page}) async {}
}

Book _book({ReadingMode mode = ReadingMode.singlePage}) => Book(
  id: 'b1',
  title: 'Physics',
  subject: 'Science',
  folderRef: '/x',
  lastOpenedPage: 1,
  preferredReadingMode: mode,
);

Future<void> _open(
  WidgetTester t, {
  ReadingMode mode = ReadingMode.singlePage,
  PageTurnAnimator? animator,
}) async {
  t.view.physicalSize = const Size(1400, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      home: ReaderScreen(
        book: _book(mode: mode),
        storage: _Storage(3),
        animator: animator,
        autosaveDelay: const Duration(hours: 1),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> _viewMode(WidgetTester t) async {
  await t.tap(find.byTooltip('Switch to View mode (Ctrl+E)'));
  await t.pumpAndSettle();
}

/// Pumps until the reader has started turning (the controller answers async).
Future<void> _pumpUntilTurning(WidgetTester t) async {
  for (var i = 0; i < 10 && find.byKey(pageTurnFrameKey).evaluate().isEmpty; i++) {
    await t.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  testWidgets('curl is the default; Next turns the page and the reader lands on page 2', (t) async {
    expect(kDefaultPageTurnStyle, PageTurnStyle.curl);
    await _open(t);
    await _viewMode(t);
    await t.tap(find.byTooltip('Next (Alt+Right)'));
    await _pumpUntilTurning(t);
    expect(find.byKey(pageTurnFrameKey), findsOneWidget);
    await t.pumpAndSettle();
    expect(find.byKey(pageTurnFrameKey), findsNothing);
    expect(find.text('Page 2 of 3'), findsOneWidget);
    expect(find.text('text 2'), findsOneWidget);
  });

  testWidgets('View mode: swipe left/right navigates through the animator', (t) async {
    await _open(t);
    await _viewMode(t);
    await t.fling(find.text('text 1'), const Offset(-400, 0), 1500);
    await t.pumpAndSettle();
    expect(find.text('Page 2 of 3'), findsOneWidget);
    await t.fling(find.text('text 2'), const Offset(400, 0), 1500);
    await t.pumpAndSettle();
    expect(find.text('Page 1 of 3'), findsOneWidget);
  });

  testWidgets('Edit mode: swipes do not turn the page and the editor keeps working', (t) async {
    await _open(t);
    expect(find.byType(TextField), findsOneWidget);
    await t.fling(find.byType(TextField), const Offset(-400, 0), 1500);
    await t.pumpAndSettle();
    expect(find.text('Page 1 of 3'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    await t.enterText(find.byType(TextField), 'still typing');
    await t.pump();
    expect(find.text('still typing'), findsOneWidget);
  });

  testWidgets('typing then turning with the curl keeps the text (T3 behaviour preserved)', (
    t,
  ) async {
    await _open(t);
    await t.enterText(find.byType(TextField), 'hello world');
    await t.pump();
    await t.tap(find.byTooltip('Next (Alt+Right)'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Previous (Alt+Left)'));
    await t.pumpAndSettle();
    expect(find.text('hello world'), findsOneWidget);
  });

  testWidgets('unfolded: next turns the right page and ends on the odd final page', (t) async {
    await _open(t, mode: ReadingMode.twoPageSpread);
    await _viewMode(t);
    expect(find.text('Pages 1\u20132 of 3'), findsOneWidget);
    await t.tap(find.byTooltip('Next (Alt+Right)'));
    await _pumpUntilTurning(t);
    expect(find.byKey(pageTurnFrameKey), findsOneWidget);
    await t.pumpAndSettle();
    expect(find.text('Page 3 of 3'), findsOneWidget);
    expect(find.text('text 3'), findsOneWidget);
  });

  testWidgets('the Page turn menu switches to Slide, which leaves the engine out', (t) async {
    await _open(t);
    await _viewMode(t);
    await t.tap(find.byTooltip('Page turn style'));
    await t.pumpAndSettle();
    await t.tap(find.text('Slide'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Next (Alt+Right)'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byKey(pageTurnFrameKey), findsNothing);
    await t.pumpAndSettle();
    expect(find.text('Page 2 of 3'), findsOneWidget);
  });

  testWidgets('a fixed animator passed to ReaderScreen hides the style menu', (t) async {
    await _open(t, animator: const SlidePageTurnAnimator());
    expect(find.byTooltip('Page turn style'), findsNothing);
  });
}
